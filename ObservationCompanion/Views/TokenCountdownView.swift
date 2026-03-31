import SwiftUI

struct TokenCountdownView: View {
    @EnvironmentObject var appState: AppState

    private var progress: Double {
        let total = Double(appState.tokenTTL)
        let remaining = Double(appState.tokenSecondsRemaining)
        guard total > 0 else { return 0 }
        return max(0, min(1, remaining / total))
    }

    private var timeString: String {
        let seconds = appState.tokenSecondsRemaining
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }

    private var barColor: Color {
        let remaining = appState.tokenSecondsRemaining
        if remaining < 300 { return .red }
        if remaining < 900 { return .orange }
        return .green
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(timeString)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(barColor)
                .monospacedDigit()

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.linear(duration: 1), value: progress)
                }
            }
            .frame(width: 60, height: 6)
        }
    }
}
