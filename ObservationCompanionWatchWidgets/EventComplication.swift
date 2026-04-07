import WidgetKit
import SwiftUI

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let emoji: String
    let typeName: String
    let cameraName: String
    let eventTimestamp: Date?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(
            date: .now, emoji: "👁️", typeName: "Motion",
            cameraName: "Camera", eventTimestamp: .now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(readEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // Generate entries every 10s over 2 minutes so the gauge animates
        let now = Date()
        let entries = (0..<12).map { i in
            readEntry(at: now.addingTimeInterval(Double(i) * 10))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(120))))
    }

    private func readEntry(at date: Date) -> ComplicationEntry {
        let defaults = UserDefaults(suiteName: "group.skylar.ObservationCompanion.watch") ?? .standard
        let emoji = defaults.string(forKey: "complication_emoji") ?? ""
        let typeName = defaults.string(forKey: "complication_typeName") ?? ""
        let cameraName = defaults.string(forKey: "complication_cameraName") ?? ""
        let ts = defaults.double(forKey: "complication_timestamp")
        let eventTimestamp = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return ComplicationEntry(
            date: date, emoji: emoji, typeName: typeName,
            cameraName: cameraName, eventTimestamp: eventTimestamp
        )
    }
}

// MARK: - Gauge helpers

private func gaugeValue(at date: Date, for eventTimestamp: Date?) -> Double {
    guard let ts = eventTimestamp else { return 0 }
    let elapsed = date.timeIntervalSince(ts)
    return min(max(elapsed / 120, 0), 1) // 0..1 over 2 minutes
}

private func gaugeColor(at date: Date, for eventTimestamp: Date?) -> Color {
    guard let ts = eventTimestamp else { return .gray }
    let elapsed = date.timeIntervalSince(ts)
    if elapsed < 20 { return .red }
    if elapsed < 60 { return .orange }
    return .yellow
}

// MARK: - Circular

struct CircularComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        Gauge(value: gaugeValue(at: entry.date, for: entry.eventTimestamp)) {
            Text(entry.emoji)
        } currentValueLabel: {
            if let ts = entry.eventTimestamp {
                Text(ts, style: .timer)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            } else {
                Text("--")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeColor(at: entry.date, for: entry.eventTimestamp))
    }
}

// MARK: - Rectangular

struct RectangularComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.typeName.isEmpty ? "No events" : entry.typeName)
                    .font(.headline)
                    .lineLimit(1)
                if let ts = entry.eventTimestamp {
                    Text(ts, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetAccentable()
    }
}

// MARK: - Inline

struct InlineComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        if let ts = entry.eventTimestamp {
            Text("\(entry.emoji) \(ts, style: .timer) \(entry.cameraName)")
        } else {
            Text("\(entry.emoji) No events")
        }
    }
}

// MARK: - Corner

#if os(watchOS)
struct CornerComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        Text(entry.emoji)
            .font(.title3)
            .widgetLabel {
                Gauge(
                    value: gaugeValue(at: entry.date, for: entry.eventTimestamp),
                    label: { Text(entry.typeName) },
                    currentValueLabel: { Text(entry.typeName) }
                )
                .gaugeStyle(.accessoryLinear)
                .tint(gaugeColor(at: entry.date, for: entry.eventTimestamp))
            }
    }
}
#endif

// MARK: - Widget

private struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: ComplicationEntry

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            CircularComplicationView(entry: entry)
        case .accessoryRectangular:
            RectangularComplicationView(entry: entry)
        case .accessoryInline:
            InlineComplicationView(entry: entry)
        #if os(watchOS)
        case .accessoryCorner:
            CornerComplicationView(entry: entry)
        #endif
        default:
            CircularComplicationView(entry: entry)
        }
    }
}

struct EventComplication: Widget {
    let kind = "EventComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Latest Event")
        .description("Shows the most recent camera event")
        #if os(watchOS)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
        #else
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        #endif
    }
}

@main
struct ObservationCompanionWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        EventComplication()
    }
}
