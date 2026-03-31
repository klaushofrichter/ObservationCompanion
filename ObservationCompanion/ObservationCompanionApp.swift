import SwiftUI
import EENApiToolkit

@main
struct ObservationCompanionApp: App {
    @StateObject private var appState: AppState
    @StateObject private var watchManager = PhoneWatchConnectivityManager()

    init() {
        let toolkit = EENToolkit(config: EENToolkitConfig(
            proxyUrl: AppConfig.proxyUrl,
            clientId: AppConfig.clientId,
            redirectUri: AppConfig.redirectUri,
            storageStrategy: .keychain,
            debug: false
        ))
        _appState = StateObject(wrappedValue: AppState(toolkit: toolkit))
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    print("[App] Activating watch manager")
                    watchManager.activate(appState: appState)
                    await checkTokenInjection()
                }
        }
    }

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
