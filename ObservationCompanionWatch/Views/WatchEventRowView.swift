import SwiftUI

struct WatchEventRowView: View {
    let event: WatchEvent
    let timeFormatter: DateFormatter

    private static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(event.typeEmoji)
                    .font(.body)
                Text(event.typeName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let seconds = Int(timeline.date.timeIntervalSince(event.timestamp))
                HStack {
                    Text(Self.hhmmFormatter.string(from: event.timestamp))
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .monospacedDigit()
                    Spacer()
                    Text(elapsedText(seconds: seconds))
                        .font(.caption2)
                        .foregroundColor(seconds < 120 ? .white : .gray.opacity(0.7))
                        .monospacedDigit()
                }
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
