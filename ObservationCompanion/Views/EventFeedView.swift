import SwiftUI
import AVFoundation
import EENApiToolkit

struct EventFeedView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedEvent: CameraEvent?
    @State private var showEventTypePicker = false
    @State private var hasNewEvents = false
    @State private var isAtTop = true
    @State private var previousEventCount = 0
    @State private var lastSelectedEventId: UUID?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var displayedEvents: [CameraEvent] {
        if appState.showSSEEvents {
            return appState.events
        }
        return appState.events.filter { !$0.type.hasPrefix("sse_") }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    showEventTypePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Events")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .accessibilityIdentifier("EventFilterButton")
                Spacer()
                if hasNewEvents {
                    Button {
                        hasNewEvents = false
                    } label: {
                        Text("new events")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                Button {
                    appState.refreshHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("EventRefreshButton")
                Button {
                    appState.isMuted.toggle()
                    if !appState.isMuted {
                        SoundPlayer.shared.play()
                    }
                } label: {
                    Image(systemName: appState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.subheadline)
                        .foregroundColor(appState.isMuted ? .gray : .blue)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("EventMuteButton")
                Text("\(displayedEvents.count)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .monospacedDigit()
                    .accessibilityIdentifier("EventCount")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.9))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("EventFeedHeader")

            Divider()
                .background(Color.gray.opacity(0.3))

            if selectedEvent != nil {
                EventDetailInline(
                    selectedEvent: $selectedEvent,
                    lastSelectedEventId: $lastSelectedEventId,
                    events: displayedEvents,
                    toolkit: appState.toolkit,
                    cameraId: appState.cameraId,
                    cameraName: appState.cameraName
                )
            } else if displayedEvents.isEmpty {
                VStack(spacing: 8) {
                    Text("Waiting for events...")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.8))
                .accessibilityIdentifier("WaitingForEvents")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            Color.clear
                                .frame(height: 0)
                                .id("top")
                                .onAppear { isAtTop = true }
                                .onDisappear { isAtTop = false }

                            ForEach(displayedEvents) { event in
                                EventRow(event: event, timeFormatter: timeFormatter, isHighlighted: event.id == lastSelectedEventId)
                                    .onTapGesture {
                                        lastSelectedEventId = event.id
                                        selectedEvent = event
                                    }
                            }
                        }
                    }
                    .background(Color.black.opacity(0.8))
                    .accessibilityIdentifier("EventList")
                    .onChange(of: hasNewEvents) {
                        if !hasNewEvents {
                            withAnimation {
                                proxy.scrollTo("top", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: displayedEvents.count) {
            let newCount = displayedEvents.count
            if newCount > previousEventCount && !isAtTop && previousEventCount > 0 {
                hasNewEvents = true
            }
            if isAtTop {
                hasNewEvents = false
            }
            previousEventCount = newCount
        }
        .sheet(isPresented: $showEventTypePicker) {
            EventTypePickerSheet(
                availableTypes: appState.availableEventTypes,
                activeTypes: appState.activeEventTypes,
                currentDuration: appState.historyDuration,
                currentShowSSEEvents: appState.showSSEEvents
            ) { newTypes, duration, showSSE in
                selectedEvent = nil
                lastSelectedEventId = nil
                appState.showSSEEvents = showSSE
                appState.applyEventFilter(newTypes, duration: duration)
            }
        }
        .onChange(of: appState.deepLinkEventId) { _, eventId in
            guard let eventId else { return }
            appState.deepLinkEventId = nil
            if let event = displayedEvents.first(where: { $0.eventId == eventId }) {
                selectedEvent = event
                lastSelectedEventId = event.id
            }
        }
    }
}

// MARK: - Event Type Picker

private struct EventTypePickerSheet: View {
    let availableTypes: [String]
    let activeTypes: [String]
    let currentDuration: TimeInterval
    let currentShowSSEEvents: Bool
    let onApply: ([String], TimeInterval, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var selectedDuration: TimeInterval = 86400
    @State private var showSSEEvents: Bool = false

    private static let durationOptions: [(label: String, value: TimeInterval)] = [
        ("10 min", 600),
        ("1 hour", 3600),
        ("24 hours", 86400),
        ("1 week", 604800),
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Button("Select All") {
                            selected = Set(availableTypes)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        Spacer()
                        Button("Select None") {
                            selected.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    .listRowBackground(Color(white: 0.15))
                }

                Section {
                    ForEach(availableTypes, id: \.self) { type in
                        Button {
                            if selected.contains(type) {
                                selected.remove(type)
                            } else {
                                selected.insert(type)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(type) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(type) ? .blue : .gray)
                                Text(EventTypeHash.displayName(type))
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                } header: {
                    Text("\(selected.count) of \(availableTypes.count) selected")
                }

                Section {
                    ForEach(Self.durationOptions, id: \.value) { option in
                        Button {
                            selectedDuration = option.value
                        } label: {
                            HStack {
                                Text(option.label)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                if selectedDuration == option.value {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .listRowBackground(Color(white: 0.15))
                    }
                } header: {
                    Text("History Duration")
                }

                Section {
                    Toggle(isOn: $showSSEEvents) {
                        Text("Show SSE Events")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color(white: 0.15))
                } header: {
                    Text("Display")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.1))
            .navigationTitle("Event Types")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        let types = availableTypes.filter { selected.contains($0) }
                        onApply(types.isEmpty ? availableTypes : types, selectedDuration, showSSEEvents)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selected = Set(activeTypes)
                selectedDuration = currentDuration
                showSSEEvents = currentShowSSEEvents
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Event Row

private struct EventRow: View {
    let event: CameraEvent
    let timeFormatter: DateFormatter
    var isHighlighted: Bool = false

    static func elapsedText(seconds: Int) -> String {
        if seconds < 0 { return "" }
        if seconds < 5 { return "just now" }
        if seconds < 120 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours < 24 { return "\(hours)h \(mins)m ago" }
        let days = hours / 24
        let hrs = hours % 24
        return "\(days)d \(hrs)h ago"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.typeEmoji)
                .font(.body)

            VStack(alignment: .leading, spacing: 1) {
                Text(EventTypeHash.displayName(event.type))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                if let confidence = event.confidenceText {
                    Text(confidence)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                if let reason = event.eevaReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(0)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(timeFormatter.string(from: event.timestamp))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .monospacedDigit()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let seconds = Int(timeline.date.timeIntervalSince(event.timestamp))
                    Text(Self.elapsedText(seconds: seconds))
                        .font(.caption2)
                        .foregroundColor(seconds < 120 ? .white : .gray.opacity(0.7))
                        .monospacedDigit()
                }
            }
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color(white: 0.25) : Color.clear)
        .contentShape(Rectangle())

        Divider()
            .background(Color.gray.opacity(0.2))
    }
}

// MARK: - Event Detail

private struct EventDetailInline: View {
    @Binding var selectedEvent: CameraEvent?
    @Binding var lastSelectedEventId: UUID?
    let events: [CameraEvent]
    let toolkit: EENToolkit
    let cameraId: String
    let cameraName: String

    // Image state
    @State private var image: UIImage?
    @State private var imageError: String?
    @State private var isLoading = false

    // Video state
    @State private var player: AVPlayer?
    @State private var isVideoMode = false
    @State private var isVideoLoading = false
    @State private var isPlaying = false
    @State private var videoError: String?
    @State private var playerObservation: NSKeyValueObservation?
    @State private var rateObservation: NSKeyValueObservation?
    @State private var timeObserver: Any?
    @State private var playbackPosition: Double = 0
    @State private var playbackDuration: Double = 0
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var videoStartDate: Date?
    @State private var seekedToEvent = false
    @State private var showCopiedToast = false

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private var event: CameraEvent {
        selectedEvent ?? events.first!
    }

    private var isInternalEvent: Bool {
        event.type.hasPrefix("sse_")
    }

    private var currentIndex: Int? {
        events.firstIndex(where: { $0.id == event.id })
    }

    private var hasPrevious: Bool {
        guard let idx = currentIndex else { return false }
        return idx > 0
    }

    private var hasNext: Bool {
        guard let idx = currentIndex else { return false }
        return idx < events.count - 1
    }

    /// Whether bounding boxes should show based on current video position.
    /// Shows when playback is within ±0.25s of the event timestamp, or when
    /// paused at the event position (seekedToEvent flag covers seek completion).
    private var showBoundingBoxesInVideo: Bool {
        guard isVideoMode, let startDate = videoStartDate else { return false }
        if seekedToEvent && !isPlaying { return true }
        let eventOffset = event.timestamp.timeIntervalSince(startDate)
        return abs(playbackPosition - eventOffset) <= 0.25
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Text(event.typeEmoji)
                        .font(.subheadline)
                        .padding(event.boundingBoxes.isEmpty ? 0 : 3)
                        .overlay(
                            event.boundingBoxes.isEmpty ? nil :
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.green, lineWidth: 2)
                        )
                    Text(EventTypeHash.displayName(event.type))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                Spacer()
                if let idx = currentIndex {
                    Text("\(idx + 1)/\(events.count)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                }
                Button { stopVideo(); selectedEvent = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.9))

            Divider()
                .background(Color.gray.opacity(0.3))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Media content
                    if isInternalEvent {
                        if !event.raw.isEmpty {
                            Text(event.raw)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .textSelection(.enabled)
                        }
                    } else if isVideoMode {
                        videoContent
                    } else if isLoading {
                        ProgressView("Loading image...")
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                    } else if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay(boundingBoxOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let imageError {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title)
                                .foregroundColor(.gray)
                            Text(imageError)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }

                    // Navigation row
                    if !isInternalEvent {
                        navigationRow
                    }

                    // Time & actor info
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Time")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                let seconds = Int(timeline.date.timeIntervalSince(event.timestamp))
                                HStack {
                                    Text(Self.fullFormatter.string(from: event.timestamp))
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(EventRow.elapsedText(seconds: seconds))
                                        .font(.subheadline)
                                        .foregroundColor(seconds < 120 ? .white : .gray.opacity(0.7))
                                }
                            }
                        }
                        if let reason = event.eevaReason {
                            DetailRow(label: "Reason", value: reason)
                        }
                        if let confidence = event.confidenceText {
                            DetailRow(label: "Confidence", value: confidence)
                        }
                        DetailRow(label: "Actor", value: cameraName)
                        if let eventId = event.eventId {
                            Button {
                                UIPasteboard.general.string = eventId
                                withAnimation { showCopiedToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showCopiedToast = false }
                                }
                            } label: {
                                HStack(alignment: .top) {
                                    DetailRow(label: "Event ID", value: eventId)
                                    Spacer()
                                    Image(systemName: showCopiedToast ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(showCopiedToast ? .green : .gray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(white: 0.1))
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontal = abs(value.translation.width) > abs(value.translation.height)
                        if horizontal && value.translation.width > 50 {
                            navigateNext()
                        } else if horizontal && value.translation.width < -50 {
                            navigatePrevious()
                        } else if !horizontal && value.translation.height > 80 {
                            stopVideo()
                            selectedEvent = nil
                        }
                    }
            )
        }
        .task(id: event.id) { await loadImage() }
        .onDisappear { stopVideo() }
    }

    // MARK: - Bounding Box Overlay

    @ViewBuilder
    private var boundingBoxOverlay: some View {
        GeometryReader { geo in
            ForEach(Array(event.boundingBoxes.enumerated()), id: \.offset) { _, box in
                Rectangle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(
                        width: box.width * geo.size.width,
                        height: box.height * geo.size.height
                    )
                    .position(
                        x: (box.x + box.width / 2) * geo.size.width,
                        y: (box.y + box.height / 2) * geo.size.height
                    )
            }
        }
    }

    // MARK: - Video Content

    @ViewBuilder
    private var videoContent: some View {
        if isVideoLoading {
            ProgressView("Loading video...")
                .frame(maxWidth: .infinity)
                .frame(height: 200)
        } else if let player {
            VideoPlayerView(player: player)
                .aspectRatio(16.0/9.0, contentMode: .fit)
                .overlay(showBoundingBoxesInVideo ? boundingBoxOverlay : nil)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { seekToEventAndPause() }
        } else if let videoError {
            VStack(spacing: 8) {
                Image(systemName: "video.slash")
                    .font(.title)
                    .foregroundColor(.gray)
                Text(videoError)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Navigation Row

    private var navigationRow: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    navigateNext()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Older")
                    }
                    .font(.subheadline)
                    .foregroundColor(hasNext ? .blue : .gray.opacity(0.4))
                }
                .disabled(!hasNext)

                Spacer()

                // Play/Pause button
                Button {
                    if isVideoMode {
                        if isPlaying {
                            player?.pause()
                        } else {
                            seekedToEvent = false
                            player?.play()
                        }
                    } else {
                        Task { await loadVideo() }
                    }
                } label: {
                    Image(systemName: isVideoMode && isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(isVideoMode && !isPlaying ? .gray : .blue)
                }

                Spacer()

                Button {
                    navigatePrevious()
                } label: {
                    HStack(spacing: 4) {
                        Text("Newer")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundColor(hasPrevious ? .blue : .gray.opacity(0.4))
                }
                .disabled(!hasPrevious)
            }
            HStack {
                if hasNext, let idx = currentIndex {
                    Text(Self.timeDelta(from: event.timestamp, to: events[idx + 1].timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
                if hasPrevious, let idx = currentIndex {
                    Text(Self.timeDelta(from: events[idx - 1].timestamp, to: event.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            // Timeline scrubber (only when video is loaded)
            if isVideoMode, player != nil {
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { playbackPosition },
                            set: { newValue in
                                playbackPosition = newValue
                                if !isScrubbing {
                                    wasPlayingBeforeScrub = isPlaying
                                    player?.pause()
                                }
                                isScrubbing = true
                                seekedToEvent = false
                            }
                        ),
                        in: 0...max(playbackDuration, 1),
                        onEditingChanged: { editing in
                            if !editing {
                                isScrubbing = false
                                let time = CMTime(seconds: playbackPosition, preferredTimescale: 600)
                                player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                                    Task { @MainActor in
                                        if finished && wasPlayingBeforeScrub {
                                            player?.play()
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .tint(.blue)

                    HStack {
                        Text(Self.formatDuration(playbackPosition))
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .monospacedDigit()
                        Spacer()
                        Text(Self.formatDuration(playbackDuration))
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Time Formatting

    static func timeDelta(from earlier: Date, to later: Date) -> String {
        let interval = abs(later.timeIntervalSince(earlier))
        if interval < 1 {
            let ms = Int(interval * 1000)
            return "\(ms)ms"
        } else if interval < 120 {
            let s = Int(interval)
            return "\(s)s"
        } else if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m)m"
        } else if interval < 86400 {
            let h = Int(interval / 3600)
            let m = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
            return "\(h)h \(m)m"
        } else {
            let d = Int(interval / 86400)
            let h = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
            return "\(d)d \(h)h"
        }
    }

    static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        guard let idx = currentIndex, idx > 0 else { return }
        stopVideo()
        image = nil
        imageError = nil
        selectedEvent = events[idx - 1]
        lastSelectedEventId = events[idx - 1].id
    }

    private func navigateNext() {
        guard let idx = currentIndex, idx < events.count - 1 else { return }
        stopVideo()
        image = nil
        imageError = nil
        selectedEvent = events[idx + 1]
        lastSelectedEventId = events[idx + 1].id
    }

    private func seekToEventAndPause() {
        guard let p = player, let startDate = videoStartDate else { return }
        p.pause()
        let offset = max(0, event.timestamp.timeIntervalSince(startDate))
        let seekTime = CMTime(seconds: offset, preferredTimescale: 600)
        p.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            Task { @MainActor in
                if finished {
                    playbackPosition = offset
                    seekedToEvent = true
                }
            }
        }
    }

    // MARK: - Image Loading

    private func loadImage() async {
        guard !isInternalEvent else { return }
        isLoading = true
        do {
            var params = GetRecordedImageParams()
            params.timestampGte = formatTimestamp(event.timestamp)
            params.type = .preview
            params.targetWidth = 640
            let result = try await toolkit.media.getRecordedImage(deviceId: cameraId, params: params)
            if let uiImage = UIImage(data: result.imageData) {
                image = uiImage
            } else {
                imageError = "Could not decode image data"
            }
        } catch {
            imageError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Video Loading

    private func loadVideo() async {
        stopVideo()
        isVideoMode = true
        isVideoLoading = true
        videoError = nil

        do {
            _ = try? await toolkit.media.initMediaSession(deviceId: cameraId)

            // Query 10 seconds before the event to get a media interval containing it
            let queryStart = event.timestamp.addingTimeInterval(-10)
            var params = ListMediaParams(
                deviceId: cameraId,
                type: .main,
                mediaType: .video,
                startTimestamp: formatTimestamp(queryStart)
            )
            params.include = ["hlsUrl"]

            let result = try await toolkit.media.listMedia(params: params)
            guard let interval = result.results.first, let hlsUrl = interval.hlsUrl else {
                videoError = "No video available at this time"
                isVideoLoading = false
                return
            }

            // Parse the interval start time to compute event offset
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            videoStartDate = isoFormatter.date(from: interval.startTimestamp)

            setupPlayer(hlsUrl: hlsUrl)
        } catch {
            videoError = error.localizedDescription
        }
        isVideoLoading = false
    }

    private func setupPlayer(hlsUrl: String) {
        guard let url = URL(string: hlsUrl) else {
            videoError = "Invalid HLS URL"
            return
        }

        let token = toolkit.authState.token ?? ""
        let headers = ["Authorization": "Bearer \(token)"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)

        // Start playback briefly so the player buffers, then seek+pause once ready
        newPlayer.play()

        playerObservation = item.observe(\.status) { item, _ in
            Task { @MainActor in
                if item.status == .readyToPlay, let startDate = videoStartDate {
                    let offset = max(0, event.timestamp.timeIntervalSince(startDate))
                    let seekTime = CMTime(seconds: offset, preferredTimescale: 600)
                    newPlayer.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                        Task { @MainActor in
                            if finished {
                                playbackPosition = offset
                            }
                        }
                    }
                } else if item.status == .failed {
                    videoError = item.error?.localizedDescription ?? "Playback failed"
                }
            }
        }

        player = newPlayer

        // Observe actual playback state
        rateObservation = newPlayer.observe(\.timeControlStatus) { player, _ in
            Task { @MainActor in
                isPlaying = player.timeControlStatus == .playing
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak newPlayer] time in
            guard !isScrubbing, let currentItem = newPlayer?.currentItem else { return }
            let duration = currentItem.duration
            if duration.isNumeric {
                playbackDuration = duration.seconds
                playbackPosition = time.seconds
            }
        }
    }

    private func stopVideo() {
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
        }
        timeObserver = nil
        player?.pause()
        player = nil
        playerObservation?.invalidate()
        playerObservation = nil
        rateObservation?.invalidate()
        rateObservation = nil
        playbackPosition = 0
        playbackDuration = 0
        isVideoMode = false
        isPlaying = false
        videoError = nil
        videoStartDate = nil
        seekedToEvent = false
    }
}

// MARK: - Camera Picker

struct CameraPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var cameras: [(id: String, name: String, isOnline: Bool)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredCameras: [(id: String, name: String, isOnline: Bool)] {
        if searchText.isEmpty { return cameras }
        let query = searchText.lowercased()
        return cameras.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading && cameras.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading cameras...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredCameras, id: \.id) { camera in
                            Button {
                                appState.switchCamera(to: camera.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(camera.isOnline ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(camera.name)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text(camera.id)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .monospaced()
                                    }
                                    Spacer()
                                    if camera.id == appState.cameraId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .listRowBackground(Color(white: 0.15))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Filter cameras")
                }
            }
            .background(Color(white: 0.1))
            .navigationTitle("Cameras (\(cameras.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadAllCameras() }
        }
        .preferredColorScheme(.dark)
    }

    private func loadAllCameras() async {
        do {
            var allCameras: [(id: String, name: String, isOnline: Bool)] = []
            var pageToken: String? = nil
            repeat {
                var params = ListCamerasParams(pageSize: 100, pageToken: pageToken)
                params.include = ["status"]
                let response = try await appState.toolkit.cameras.list(params: params)
                allCameras.append(contentsOf: response.results.map { cam in
                    let isOnline = cam.status?.effectiveStatus == .online || cam.status?.effectiveStatus == .streaming
                    return (cam.id, cam.name, isOnline)
                })
                cameras = allCameras
                pageToken = response.nextPageToken
            } while pageToken != nil
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
                .textSelection(.enabled)
        }
    }
}
