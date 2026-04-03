import SwiftUI
import BackgroundTasks
import EENSwiftToolkit
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct ObservationCompanionApp: App {
    @StateObject private var appState: AppState
    @StateObject private var watchManager = PhoneWatchConnectivityManager()

    static let bgTaskId = "skylar.ObservationCompanion.refreshLiveActivity"

    init() {
        let toolkit = EENToolkit(config: EENToolkitConfig(
            proxyUrl: AppConfig.proxyUrl,
            clientId: AppConfig.clientId,
            redirectUri: AppConfig.redirectUri,
            storageStrategy: .keychain,
            debug: false
        ))
        _appState = StateObject(wrappedValue: AppState(toolkit: toolkit))

        #if canImport(ActivityKit)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.bgTaskId,
            using: nil
        ) { task in
            if let bgTask = task as? BGAppRefreshTask {
                Self.handleBackgroundRefresh(task: bgTask)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    #if canImport(ActivityKit)
                    // End Live Activities left over from a previous session
                    for activity in Activity<MonitoringActivityAttributes>.activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                    #endif
                    print("[App] Activating watch manager")
                    watchManager.activate(appState: appState)
                    await checkTokenInjection()
                }
                .onChange(of: appState.connectionState) { newState in
                    if case .live = newState {
                        Self.scheduleBackgroundRefresh()
                    }
                }
        }
    }

    // MARK: - Background Refresh

    static func scheduleBackgroundRefresh() {
        #if canImport(ActivityKit)
        let request = BGAppRefreshTaskRequest(identifier: bgTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BGTask] Failed to schedule: \(error)")
        }
        #endif
    }

    #if canImport(ActivityKit)
    static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleBackgroundRefresh()

        // Check if there's an active Live Activity
        guard let activity = Activity<MonitoringActivityAttributes>.activities.first else {
            task.setTaskCompleted(success: true)
            return
        }

        // Read persisted session info
        let defaults = UserDefaults.standard
        guard let cameraId = defaults.string(forKey: AppState.BGKeys.cameraId),
              let cameraName = defaults.string(forKey: AppState.BGKeys.cameraName),
              let eventTypesData = defaults.data(forKey: AppState.BGKeys.activeEventTypes),
              let eventTypes = try? JSONDecoder().decode([String].self, from: eventTypesData)
        else {
            task.setTaskCompleted(success: true)
            return
        }

        let bgTask = Task {
            do {
                // Create a fresh toolkit with keychain credentials
                let toolkit = EENToolkit(config: EENToolkitConfig(
                    proxyUrl: AppConfig.proxyUrl,
                    clientId: AppConfig.clientId,
                    redirectUri: AppConfig.redirectUri,
                    storageStrategy: .keychain,
                    debug: false
                ))
                let restored = await toolkit.restoreSession()
                guard restored else {
                    task.setTaskCompleted(success: false)
                    return
                }

                // Fetch latest events
                var params = ListEventsParams(
                    actor: "camera:\(cameraId)",
                    typeIn: eventTypes,
                    startTimestampGte: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
                    pageSize: 1
                )
                params.sort = "-startTimestamp"

                let result = try await toolkit.events.list(params: params)
                guard let latest = result.results.first else {
                    task.setTaskCompleted(success: true)
                    return
                }

                let timestamp = ISO8601DateFormatter().date(from: latest.startTimestamp) ?? Date()
                let event = CameraEvent(
                    type: latest.type,
                    actorId: latest.actorId,
                    description: EventTypeHash.eventDescription(type: latest.type, startTimestamp: latest.startTimestamp),
                    timestamp: timestamp,
                    eventId: latest.id
                )

                let previousCount = activity.content.state.eventCount
                let updatedState = MonitoringActivityAttributes.ContentState(
                    cameraName: cameraName,
                    latestEventEmoji: event.typeEmoji,
                    latestEventSymbol: event.typeSymbol,
                    latestEventDescription: event.description,
                    eventCount: previousCount,
                    lastEventTimestamp: timestamp,
                    latestEventId: event.eventId
                )

                await activity.update(ActivityContent(
                    state: updatedState,
                    staleDate: Date(timeIntervalSinceNow: LiveActivityManager.staleDuration)
                ))
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            bgTask.cancel()
        }
    }
    #endif

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }

        let host = url.host(percentEncoded: false) ?? url.host
        if host == "callback" {
            // OAuth callback
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let code = components?.queryItems?.first(where: { $0.name == "code" })?.value {
                let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
                Task {
                    do {
                        try await appState.toolkit.auth.handleCallback(code: code, state: state)
                        appState.configureOAuth()
                    } catch {
                        appState.connectionState = .error("OAuth failed: \(error.localizedDescription)")
                    }
                }
            }
        } else if host == "dismiss" {
            #if canImport(ActivityKit)
            appState.dismissLiveActivity()
            #endif
        } else if host == "event" {
            // Dynamic Island deep link to event detail
            let eventId = url.pathComponents.dropFirst().first
            appState.deepLinkEventId = eventId
        } else {
            // QR code / deep link
            appState.handleViewerURL(url)
        }
    }

    private func checkTokenInjection() async {
        // Check environment variables for token injection (testing/development)
        let env = ProcessInfo.processInfo.environment
        if let token = env["EEN_TOKEN"],
           let baseUrl = env["EEN_BASE_URL"],
           let cameraId = env["EEN_CAMERA_ID"] {
            let events = env["EEN_EVENT_HASHES"] ?? ""
            let ttl = env["EEN_TTL"].flatMap { Double($0) }
            appState.configureQRCode(token: token, cameraId: cameraId, baseUrl: baseUrl, eventHashes: events, ttl: ttl)
            return
        }

        // Check for file-based token injection
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let fileUrl = docsDir?.appendingPathComponent("een_session.json"),
           let data = try? Data(contentsOf: fileUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = json["token"] as? String,
           let baseUrl = json["baseUrl"] as? String,
           let cameraId = json["cameraId"] as? String {
            let events = json["events"] as? String ?? ""
            let ttl = json["ttl"] as? Double
            appState.configureQRCode(token: token, cameraId: cameraId, baseUrl: baseUrl, eventHashes: events, ttl: ttl)
            // Clean up file
            try? FileManager.default.removeItem(at: fileUrl)
            return
        }

        // Try to restore OAuth session
        let restored = await appState.toolkit.restoreSession()
        if restored {
            appState.configureOAuth()
        }
    }
}
