import Foundation

enum AppConfig {
    static let proxyUrl = ProcessInfo.processInfo.environment["EEN_PROXY_URL"]
        ?? "https://een-mobile-proxy.klaushofrichter.workers.dev"

    static let clientId = ProcessInfo.processInfo.environment["EEN_CLIENT_ID"]
        ?? "PREVIEW-KLAUS-MOBILE"

    /// OAuth redirect goes to the proxy, which returns the code via redirect
    static let redirectUri = "https://een-mobile-proxy.klaushofrichter.workers.dev"

    /// URL scheme for QR codes and deep links
    static let urlScheme = "eenobserve"
}
