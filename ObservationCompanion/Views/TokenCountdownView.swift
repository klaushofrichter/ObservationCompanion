import SwiftUI

struct TokenCountdownView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAbout = false

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

    private var timerColor: Color {
        appState.tokenSecondsRemaining < 900 ? .red : .green
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(timeString)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(timerColor)
                .monospacedDigit()

            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}
