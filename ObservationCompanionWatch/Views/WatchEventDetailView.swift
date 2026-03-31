import SwiftUI

struct WatchEventDetailView: View {
    @Binding var eventId: UUID
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var loadFailed = false

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private var event: WatchEvent? {
        connectivityManager.events.first { $0.id == eventId }
    }

    private var currentIndex: Int? {
        connectivityManager.events.firstIndex { $0.id == eventId }
    }

    var body: some View {
        if let event {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Recorded image
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if let imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay(boundingBoxOverlay(for: event))
                            .cornerRadius(8)
                    } else if loadFailed {
                        HStack {
                            Image(systemName: "photo.slash")
                            Text("No image")
                                .font(.caption2)
                        }
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }

                    HStack {
                        Text(event.typeEmoji)
                            .font(.title3)
                        Text(event.typeName)
                            .font(.headline)
                    }

                    Divider()

                    Label(event.cameraName, systemImage: "video")
                        .font(.caption2)
                        .foregroundColor(.blue)

                    Label(Self.fullFormatter.string(from: event.timestamp), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .monospacedDigit()

                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let seconds = Int(timeline.date.timeIntervalSince(event.timestamp))
                        Label(elapsedText(seconds: seconds), systemImage: "timer")
                            .font(.caption2)
                            .foregroundColor(seconds < 120 ? .white : .gray)
                    }

                    if let reason = event.eevaReason {
                        Divider()
                        Label(reason, systemImage: "brain")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }

                    if let confidence = event.confidenceText {
                        Divider()
                        Label(confidence, systemImage: "sparkle.magnifyingglass")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("")
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < -50 {
                            // Swipe left → newer event (lower index)
                            navigateNewer()
                        } else if value.translation.width > 50 {
                            // Swipe right → older event (higher index)
                            navigateOlder()
                        }
                    }
            )
            .task(id: eventId) {
                await loadImage()
            }
        }
    }

    private func navigateNewer() {
        guard let idx = currentIndex, idx > 0 else { return }
        imageData = nil
        loadFailed = false
        eventId = connectivityManager.events[idx - 1].id
    }

    private func navigateOlder() {
        guard let idx = currentIndex, idx < connectivityManager.events.count - 1 else { return }
        imageData = nil
        loadFailed = false
        eventId = connectivityManager.events[idx + 1].id
    }

    private func loadImage() async {
        guard let event else { return }
        isLoading = true
        await withCheckedContinuation { continuation in
            connectivityManager.requestImage(for: event) { data in
                Task { @MainActor in
                    if let data {
                        imageData = data
                    } else {
                        loadFailed = true
                    }
                    isLoading = false
                    continuation.resume()
                }
            }
        }
    }

    @ViewBuilder
    private func boundingBoxOverlay(for event: WatchEvent) -> some View {
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

    private func elapsedText(seconds: Int) -> String {
        if seconds < 0 { return "" }
        if seconds < 5 { return "just now" }
        if seconds < 120 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m ago"
    }
}
