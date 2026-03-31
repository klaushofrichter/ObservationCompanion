import Foundation
import AVFoundation
import Combine
import EENApiToolkit
#if canImport(ActivityKit)
import ActivityKit
#endif

enum AppError: LocalizedError {
    case noHLSUrl

    var errorDescription: String? {
        switch self {
        case .noHLSUrl: return "No HLS URL available for this camera"
        }
    }
}

enum ConnectionState: Equatable {
    case scanning
    case connecting
    case live
    case expired
    case error(String)

    nonisolated static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.scanning, .scanning),
             (.connecting, .connecting),
             (.live, .live),
             (.expired, .expired):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

enum AuthMode: Equatable {
    case qrCode(expiresAt: Date)
    case oauth

    nonisolated static func == (lhs: AuthMode, rhs: AuthMode) -> Bool {
        switch (lhs, rhs) {
        case (.oauth, .oauth): return true
        case (.qrCode(let a), .qrCode(let b)): return a == b
        default: return false
        }
    }
}

class AppState: ObservableObject {
    static let defaultTokenTTL: TimeInterval = 3600

    @Published var connectionState: ConnectionState = .scanning
    @Published var authMode: AuthMode?
    @Published var cameraName: String = ""
    @Published var events: [CameraEvent] = []
    @Published var tokenSecondsRemaining: Int = 0
    @Published var tokenTTL: TimeInterval = 3600
    @Published var availableEventTypes: [String] = []
    @Published var activeEventTypes: [String] = []
    @Published var historyDuration: TimeInterval = 86400
    @Published var isMuted: Bool = true
    @Published var showSSEEvents: Bool = false
    @Published var deepLinkEventId: String?
    @Published var liveBoundingBoxes: [BoundingBox] = []
    @Published var hlsLatency: TimeInterval = 5.0

    // HLS player
    @Published var hlsPlayer: AVPlayer?
    @Published var isVideoPlaying: Bool = false
    @Published var videoError: String?

    private(set) var cameraId: String = ""
    private var eventHashes: String = ""

    let toolkit: EENToolkit

    #if canImport(ActivityKit)
    private let liveActivityManager = LiveActivityManager()
    #endif

    private var tokenTimer: Timer?
    private var latencyTimer: Timer?
    private var overlayTimer: Timer?
    private var overlayQueue: [(boxes: [BoundingBox], showAt: Date, hideAt: Date)] = []
    private static let maxPendingOverlays = 10
    private var sseConnection: SSEConnection?
    private var subscriptionId: String?
    private var playerObservation: NSKeyValueObservation?

    init(toolkit: EENToolkit) {
        self.toolkit = toolkit
    }

    deinit {
        tokenTimer?.invalidate()
        latencyTimer?.invalidate()
        overlayTimer?.invalidate()
        sseConnection?.close()
        hlsPlayer?.pause()
        playerObservation?.invalidate()
        if let subId = subscriptionId {
            let tk = toolkit
            Task { try? await tk.eventSubscriptions.delete(id: subId) }
        }
    }

    // MARK: - QR Code Flow

    func handleViewerURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == AppConfig.urlScheme.lowercased() else {
            connectionState = .error("Invalid URL scheme: '\(url.scheme ?? "nil")' (expected '\(AppConfig.urlScheme)')")
            return
        }

        // OAuth callback - ignore here, handled by app entry point
        let host = url.host(percentEncoded: false) ?? url.host
        if host == "callback" { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            connectionState = .error("Could not parse URL parameters")
            return
        }

        let token = queryItems.first(where: { $0.name == "token" })?.value
        let cam = queryItems.first(where: { $0.name == "cam" })?.value
        let base = queryItems.first(where: { $0.name == "base" })?.value
        let events = queryItems.first(where: { $0.name == "events" })?.value ?? ""
        let ttlString = queryItems.first(where: { $0.name == "ttl" })?.value
        let ttl: TimeInterval? = ttlString.flatMap { Double($0) }
            .map { $0 - Date().timeIntervalSince1970 }
            .flatMap { $0 > 0 ? $0 : nil }

        guard let token, !token.isEmpty,
              let cam, !cam.isEmpty,
              let base, !base.isEmpty else {
            let found = queryItems.map { $0.name }.joined(separator: ", ")
            connectionState = .error("Missing parameters. Found: [\(found)]")
            return
        }

        configureQRCode(token: token, cameraId: cam, baseUrl: base, eventHashes: events, ttl: ttl)
    }

    func configureQRCode(token: String, cameraId: String, baseUrl: String, eventHashes: String = "", ttl: TimeInterval? = nil) {
        cleanup()

        self.cameraId = cameraId
        self.eventHashes = eventHashes
        let effectiveTTL = ttl ?? Self.defaultTokenTTL
        self.tokenTTL = effectiveTTL

        let normalizedBase = baseUrl.hasPrefix("http") ? baseUrl : "https://\(baseUrl)"

        // Inject token into toolkit's auth state
        toolkit.authState.inject(token: token, baseUrl: normalizedBase, expiresIn: Int(effectiveTTL))

        let expiresAt = Date().addingTimeInterval(effectiveTTL)
        self.authMode = .qrCode(expiresAt: expiresAt)
        self.connectionState = .connecting
        self.events = []

        startTokenCountdown(expiresAt: expiresAt)
        startConnection()
    }

    // MARK: - OAuth Flow

    func configureOAuth() {
        self.authMode = .oauth
        self.connectionState = .connecting
        self.events = []

        // Start token countdown from OAuth token expiration
        if let expiration = toolkit.authState.tokenExpiration {
            let ttl = expiration.timeIntervalSinceNow
            if ttl > 0 {
                self.tokenTTL = ttl
                startTokenCountdown(expiresAt: expiration)
            }
        }

        // Select first available camera
        Task {
            do {
                let result = try await toolkit.cameras.list(params: ListCamerasParams(pageSize: 1))
                guard let camera = result.results.first else {
                    self.connectionState = .error("No cameras available on this account")
                    return
                }
                self.cameraId = camera.id
                self.cameraName = camera.name
                self.startConnection()
            } catch {
                self.connectionState = .error("Failed to load cameras: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Connection

    private func startConnection() {
        Task {
            // Media session init is best-effort (may not exist on all API versions)
            Task { try? await toolkit.media.initMediaSession(deviceId: cameraId) }

            await connectCamera { fetchedTypes in
                if eventHashes.isEmpty {
                    return fetchedTypes
                }
                let lookup = EventTypeHash.buildLookup(fetchedTypes)
                let resolved = EventTypeHash.resolve(hashString: eventHashes, lookup: lookup)
                return resolved.isEmpty ? fetchedTypes : resolved
            }
        }
    }

    /// Shared connection logic used by both `startConnection()` and `switchCamera()`.
    /// The `selectActiveTypes` closure receives the fetched event types and returns the active set.
    private func connectCamera(selectActiveTypes: ([String]) -> [String]) async {
        do {
            async let cameraFetch = toolkit.cameras.get(id: cameraId)
            async let typesFetch = toolkit.events.listFieldValues(actor: "camera:\(cameraId)")
            async let feedsFetch = fetchHLSUrl()

            let camera = try await cameraFetch
            self.cameraName = camera.name

            let fieldValues = try await typesFetch
            let fetchedTypes = fieldValues.type
            self.availableEventTypes = fetchedTypes.sorted()
            self.activeEventTypes = selectActiveTypes(fetchedTypes)

            let hlsUrl = try await feedsFetch
            setupHLSPlayer(hlsUrl: hlsUrl)

            await startSSESubscription()

            self.connectionState = .live
        } catch {
            self.connectionState = .error(error.localizedDescription)
        }
    }

    private func fetchHLSUrl() async throws -> String {
        var params = ListFeedsParams()
        params.deviceId = cameraId
        params.type = .main
        params.include = ["hlsUrl"]
        let feeds = try await toolkit.feeds.list(params: params)
        guard let hlsUrl = feeds.results.first?.hlsUrl else {
            throw AppError.noHLSUrl
        }
        return hlsUrl
    }

    // MARK: - HLS Player

    private func setupHLSPlayer(hlsUrl: String) {
        guard let url = URL(string: hlsUrl) else {
            videoError = "Invalid HLS URL"
            return
        }
        let token = toolkit.authState.token ?? ""
        let headers = ["Authorization": "Bearer \(token)"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)

        playerObservation = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                switch item.status {
                case .readyToPlay:
                    self?.isVideoPlaying = true
                case .failed:
                    self?.videoError = item.error?.localizedDescription ?? "Playback failed"
                default:
                    break
                }
            }
        }

        self.hlsPlayer = player
        self.isVideoPlaying = false
        self.videoError = nil
        player.play()
        startLatencyMeasurement()
    }

    private func startLatencyMeasurement() {
        latencyTimer?.invalidate()
        latencyTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.measureLatency()
            }
        }
    }

    private func measureLatency() {
        guard let item = hlsPlayer?.currentItem,
              item.status == .readyToPlay,
              let programDate = item.currentDate() else { return }
        let latency = Date().timeIntervalSince(programDate)
        if latency > 0 && latency < 60 {
            hlsLatency = latency
        }
    }

    // MARK: - Bounding Box Overlay Queue

    private func scheduleOverlay(boxes: [BoundingBox]) {
        let showDelay = max(hlsLatency, 0.5)
        let now = Date()
        let showAt = now.addingTimeInterval(showDelay)
        let hideAt = showAt.addingTimeInterval(1.0)
        overlayQueue.append((boxes: boxes, showAt: showAt, hideAt: hideAt))

        // Evict oldest if over capacity
        if overlayQueue.count > Self.maxPendingOverlays {
            overlayQueue.removeFirst()
        }

        // Start tick timer if not running
        if overlayTimer == nil {
            overlayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.tickOverlays()
                }
            }
        }
    }

    private func tickOverlays() {
        let now = Date()

        // Remove expired entries
        overlayQueue.removeAll { now >= $0.hideAt }

        // Find the latest entry that should be visible now
        let visible = overlayQueue.last { now >= $0.showAt && now < $0.hideAt }
        liveBoundingBoxes = visible?.boxes ?? []

        // Stop timer if queue is empty
        if overlayQueue.isEmpty {
            overlayTimer?.invalidate()
            overlayTimer = nil
        }
    }

    private func cancelPendingOverlays() {
        overlayTimer?.invalidate()
        overlayTimer = nil
        overlayQueue.removeAll()
        liveBoundingBoxes = []
    }

    // MARK: - SSE Events

    private func startSSESubscription() async {
        // Clean up previous
        sseConnection?.close()
        if let subId = subscriptionId {
            try? await toolkit.eventSubscriptions.delete(id: subId)
        }

        do {
            let subscription = try await toolkit.eventSubscriptions.create(
                params: CreateEventSubscriptionParams(
                    sseFilters: [FilterCreate(
                        actors: ["camera:\(cameraId)"],
                        types: activeEventTypes.map { EventTypeFilter(id: $0) }
                    )]
                )
            )
            self.subscriptionId = subscription.id

            guard case .sse(let sseUrl) = subscription.deliveryConfig, let url = sseUrl else {
                self.events.insert(CameraEvent(type: "sse_error", actorId: cameraId, description: "No SSE URL in subscription response"), at: 0)
                return
            }

            // Start Live Activity before loading history
            #if canImport(ActivityKit)
            liveActivityManager.startMonitoring(cameraName: cameraName)
            #endif

            // Load history first
            await loadHistory()

            // Connect SSE
            self.events.insert(CameraEvent(type: "sse_connecting", actorId: cameraId, description: "Connecting to event stream..."), at: 0)

            let connection = toolkit.eventSubscriptions.connect(
                sseUrl: url,
                options: SSEConnectionOptions(
                    onEvent: { [weak self] event in
                        Task { @MainActor [weak self] in
                            self?.handleSSEEvent(event)
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor [weak self] in
                            self?.events.insert(CameraEvent(
                                type: "sse_error",
                                actorId: self?.cameraId ?? "",
                                description: "SSE error: \(error.localizedDescription)"
                            ), at: 0)
                        }
                    },
                    onStatusChange: { [weak self] status in
                        Task { @MainActor [weak self] in
                            if status == .connected {
                                self?.events.insert(CameraEvent(
                                    type: "sse_connected",
                                    actorId: self?.cameraId ?? "",
                                    description: "Connected to event stream"
                                ), at: 0)
                                #if canImport(ActivityKit)
                                self?.updateLiveActivity()
                                #endif
                            }
                        }
                    }
                )
            )
            self.sseConnection = connection
        } catch {
            self.events.insert(CameraEvent(
                type: "sse_error",
                actorId: cameraId,
                description: "Failed to create subscription: \(error.localizedDescription)"
            ), at: 0)
        }
    }

    private func handleSSEEvent(_ sseEvent: SSEEvent) {
        let description = EventTypeHash.eventDescription(type: sseEvent.type, startTimestamp: sseEvent.startTimestamp)
        let date = EventTypeHash.isoFormatter.date(from: sseEvent.startTimestamp) ?? Date()
        let boxes = sseEvent.data.map { CameraEvent.extractBoundingBoxes(from: $0) } ?? []
        let reason: String? = (sseEvent.type == "een.eevaQueryEvent.v1")
            ? sseEvent.data.flatMap { CameraEvent.extractEevaReason(from: $0) }
            : nil
        let confidences = sseEvent.data.map { CameraEvent.extractConfidences(from: $0) } ?? []
        let event = CameraEvent(
            type: sseEvent.type,
            actorId: sseEvent.actorId,
            description: description,
            timestamp: date,
            eventId: sseEvent.id,
            boundingBoxes: boxes,
            eevaReason: reason,
            confidences: confidences
        )
        insertEvent(event)

        if !event.type.hasPrefix("sse_") {
            #if canImport(ActivityKit)
            liveActivityManager.undismiss(cameraName: cameraName)
            updateLiveActivity()
            #endif
        }

        if !boxes.isEmpty {
            scheduleOverlay(boxes: boxes)
        }

        if !event.type.hasPrefix("sse_") && !isMuted {
            SoundPlayer.shared.play()
        }
    }

    // MARK: - History

    private func loadHistory() async {
        let startTime = formatTimestamp(Date().addingTimeInterval(-historyDuration))
        let endTime = formatTimestamp(Date())

        do {
            var params = ListEventsParams(
                actor: "camera:\(cameraId)",
                typeIn: activeEventTypes,
                startTimestampGte: startTime,
                pageSize: 250
            )
            params.startTimestampLte = endTime
            params.sort = "-startTimestamp"
            params.include = EventDataSchemas.includeParameters(for: activeEventTypes)

            let result = try await toolkit.events.list(params: params)
            let historyEvents = result.results.map { apiEvent in
                CameraEvent(
                    type: apiEvent.type,
                    actorId: apiEvent.actorId,
                    description: EventTypeHash.eventDescription(type: apiEvent.type, startTimestamp: apiEvent.startTimestamp),
                    timestamp: EventTypeHash.isoFormatter.date(from: apiEvent.startTimestamp) ?? Date(),
                    eventId: apiEvent.id,
                    boundingBoxes: CameraEvent.extractBoundingBoxes(from: apiEvent.data),
                    eevaReason: apiEvent.type == "een.eevaQueryEvent.v1" ? CameraEvent.extractEevaReason(from: apiEvent.data) : nil,
                    confidences: CameraEvent.extractConfidences(from: apiEvent.data)
                )
            }
            mergeEvents(historyEvents)
            #if canImport(ActivityKit)
            updateLiveActivity()
            #endif
        } catch {
            self.events.insert(CameraEvent(
                type: "sse_error",
                actorId: cameraId,
                description: "History load failed: \(error.localizedDescription)"
            ), at: 0)
        }
    }

    func refreshHistory() {
        events = []
        Task { await loadHistory() }
    }

    // MARK: - Camera Switching

    func switchCamera(to newCameraId: String) {
        guard newCameraId != cameraId else { return }

        #if canImport(ActivityKit)
        liveActivityManager.endMonitoring()
        #endif
        sseConnection?.close()
        sseConnection = nil
        hlsPlayer?.pause()
        hlsPlayer = nil
        playerObservation?.invalidate()
        latencyTimer?.invalidate()
        latencyTimer = nil
        cancelPendingOverlays()
        isVideoPlaying = false
        videoError = nil
        events = []
        connectionState = .connecting
        cameraId = newCameraId

        let previousActiveTypes = activeEventTypes

        Task {
            await connectCamera { fetchedTypes in
                let intersection = previousActiveTypes.filter { fetchedTypes.contains($0) }
                return intersection.isEmpty ? fetchedTypes : intersection
            }
        }
    }

    // MARK: - Event Filter

    func applyEventFilter(_ types: [String], duration: TimeInterval? = nil) {
        activeEventTypes = types
        if let duration { historyDuration = duration }
        events = []
        Task { await startSSESubscription() }
    }

    // MARK: - Token Countdown (QR mode only)

    private func startTokenCountdown(expiresAt: Date) {
        tokenTimer?.invalidate()
        updateTokenRemaining(expiresAt: expiresAt)
        tokenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTokenRemaining(expiresAt: expiresAt)
            }
        }
    }

    private func updateTokenRemaining(expiresAt: Date) {
        let remaining = Int(expiresAt.timeIntervalSinceNow)
        if remaining <= 0 {
            // In OAuth mode, the toolkit auto-refreshes the token — check for new expiration
            if authMode == .oauth,
               let newExpiration = toolkit.authState.tokenExpiration,
               newExpiration.timeIntervalSinceNow > 0 {
                let newTTL = newExpiration.timeIntervalSinceNow
                tokenTTL = newTTL
                tokenTimer?.invalidate()
                startTokenCountdown(expiresAt: newExpiration)
                return
            }
            tokenSecondsRemaining = 0
            tokenTimer?.invalidate()
            tokenTimer = nil
            latencyTimer?.invalidate()
            latencyTimer = nil
            cancelPendingOverlays()
            hlsPlayer?.pause()
            sseConnection?.close()
            connectionState = .expired
        } else {
            tokenSecondsRemaining = remaining
        }
    }

    // MARK: - Helpers

    #if canImport(ActivityKit)
    /// Updates the Dynamic Island to reflect the most recent real event in the list.
    private func updateLiveActivity() {
        let realEvents = events.filter { !$0.type.hasPrefix("sse_") }
        if let latest = realEvents.first {
            liveActivityManager.updateWithEvent(
                cameraName: cameraName,
                emoji: latest.typeEmoji,
                description: latest.description,
                eventCount: realEvents.count,
                timestamp: latest.timestamp,
                eventId: latest.eventId
            )
        } else {
            liveActivityManager.updateWithEvent(
                cameraName: cameraName,
                emoji: "",
                description: "No events",
                eventCount: 0
            )
        }
    }

    func dismissLiveActivity() {
        liveActivityManager.dismiss()
    }
    #endif

    private func insertEvent(_ event: CameraEvent) {
        if let eventId = event.eventId,
           let idx = events.firstIndex(where: { $0.eventId == eventId }) {
            events[idx] = event
        } else {
            let insertIndex = events.firstIndex(where: { $0.timestamp < event.timestamp }) ?? events.endIndex
            events.insert(event, at: insertIndex)
            if events.count > 250 {
                events.removeLast()
            }
        }
    }

    /// Batch-merge events into the list with a single @Published mutation.
    private func mergeEvents(_ newEvents: [CameraEvent]) {
        guard !newEvents.isEmpty else { return }
        var merged = events
        let existingIds = Set(merged.compactMap(\.eventId))
        for event in newEvents {
            if let eventId = event.eventId, existingIds.contains(eventId) {
                if let idx = merged.firstIndex(where: { $0.eventId == eventId }) {
                    merged[idx] = event
                }
            } else {
                let insertIndex = merged.firstIndex(where: { $0.timestamp < event.timestamp }) ?? merged.endIndex
                merged.insert(event, at: insertIndex)
            }
        }
        if merged.count > 100 {
            merged = Array(merged.prefix(250))
        }
        events = merged
    }

    func reset() {
        cleanup()
        connectionState = .scanning
        authMode = nil
        cameraId = ""
        cameraName = ""
        eventHashes = ""
        events = []
        availableEventTypes = []
        activeEventTypes = []
    }

    private func cleanup() {
        #if canImport(ActivityKit)
        liveActivityManager.endMonitoring()
        #endif
        tokenTimer?.invalidate()
        tokenTimer = nil
        latencyTimer?.invalidate()
        latencyTimer = nil
        cancelPendingOverlays()
        sseConnection?.close()
        sseConnection = nil
        hlsPlayer?.pause()
        hlsPlayer = nil
        playerObservation?.invalidate()
        playerObservation = nil
        isVideoPlaying = false
        videoError = nil

        if let subId = subscriptionId {
            let tk = toolkit
            Task { try? await tk.eventSubscriptions.delete(id: subId) }
            subscriptionId = nil
        }
    }
}
