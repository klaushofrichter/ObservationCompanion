import SwiftUI

@main
struct ObservationCompanionWatchApp: App {
    @StateObject private var connectivityManager = WatchConnectivityManager()

    var body: some Scene {
        WindowGroup {
            WatchEventListView()
                .environmentObject(connectivityManager)
        }
    }
}
