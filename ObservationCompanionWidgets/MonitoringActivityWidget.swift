import WidgetKit
import SwiftUI

@main
struct ObservationCompanionWidgetBundle: WidgetBundle {
    var body: some Widget {
        MonitoringActivityWidget()
    }
}

struct MonitoringActivityWidget: Widget {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }()

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitoringActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            HStack(spacing: 12) {
                if context.state.latestEventEmoji.isEmpty {
                    appIcon(size: 40, cornerRadius: 8)
                } else {
                    Text(context.state.latestEventEmoji)
                        .font(.largeTitle)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.cameraName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Self.eventTypeName(context.state.latestEventDescription))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }
                Spacer()
                if let timestamp = context.state.lastEventTimestamp {
                    Text(timestamp, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "eenobserve://dismiss")!) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.latestEventEmoji.isEmpty {
                        appIcon(size: 28, cornerRadius: 6)
                    } else {
                        Text(context.state.latestEventEmoji)
                            .font(.title)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(Self.eventTypeName(context.state.latestEventDescription))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(context.state.cameraName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    if let timestamp = context.state.lastEventTimestamp {
                        (Text(Self.timeFormatter.string(from: timestamp) + " · ")
                         + Text(timestamp, style: .relative)
                         + Text(" ago"))
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(.leading, 16)
                    }
                }
            } compactLeading: {
                if context.state.latestEventEmoji.isEmpty {
                    appIcon(size: 24, cornerRadius: 6)
                } else {
                    Text(context.state.latestEventEmoji)
                        .font(.body)
                        .minimumScaleFactor(0.5)
                }
            } compactTrailing: {
                if let timestamp = context.state.lastEventTimestamp {
                    Text(timestamp, style: .timer)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: 48)
                }
            } minimal: {
                if context.state.latestEventEmoji.isEmpty {
                    appIcon(size: 16, cornerRadius: 4)
                } else {
                    Text(context.state.latestEventEmoji)
                        .font(.caption)
                        .minimumScaleFactor(0.5)
                }
            }
            .widgetURL(Self.eventURL(context.state.latestEventId))
        }
    }

    /// Strips the "@ timestamp" suffix from the event description
    private static func eventTypeName(_ description: String) -> String {
        if let range = description.range(of: " @ ") {
            return String(description[..<range.lowerBound])
        }
        return description
    }

    private static func eventURL(_ eventId: String?) -> URL? {
        guard let eventId else { return nil }
        return URL(string: "eenobserve://event/\(eventId)")
    }
}

// MARK: - App Icon Helper

@ViewBuilder
private func appIcon(size: CGFloat, cornerRadius: CGFloat) -> some View {
    Image("AppIconImage")
        .resizable()
        .interpolation(.high)
        .renderingMode(.original)
        .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
}
