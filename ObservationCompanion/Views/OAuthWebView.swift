import SwiftUI
import WebKit
import EENSwiftToolkit

// MARK: - Warmup view

/// A hidden WKWebView placed in the view hierarchy to force the web content
/// process to start. Loads about:blank so the process is fully warmed up.
/// The user never interacts with this view.
struct OAuthWarmupWebView: UIViewRepresentable {
    let url: URL
    let onReady: () -> Void

    func makeCoordinator() -> WarmupCoordinator {
        WarmupCoordinator(onReady: onReady)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class WarmupCoordinator: NSObject, WKNavigationDelegate {
        let onReady: () -> Void
        private var fired = false

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !fired else { return }
            fired = true
            onReady()
        }
    }
}

// MARK: - OAuth web view for the sheet

struct OAuthWebView: UIViewRepresentable {
    let authUrl: URL
    let redirectUri: String
    let onCallback: (String, String?) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(redirectUri: redirectUri, onCallback: onCallback, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        // Inject a viewport meta tag so the login page fits the sheet width
        // and does not expand when the keyboard / password manager appears.
        let viewportScript = WKUserScript(
            source: """
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
            }
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(viewportScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.minimumZoomScale = 1.0
        webView.load(URLRequest(url: authUrl))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let redirectUri: String
        let onCallback: (String, String?) -> Void
        let onError: (String) -> Void
        private var callbackHandled = false

        init(redirectUri: String, onCallback: @escaping (String, String?) -> Void, onError: @escaping (String) -> Void) {
            self.redirectUri = redirectUri
            self.onCallback = onCallback
            self.onError = onError
        }

        func webView(_ webView: WKWebView,
                      decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let urlString = url.absoluteString
            let normalizedRedirect = redirectUri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if urlString.hasPrefix(normalizedRedirect), !callbackHandled {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let code = components?.queryItems?.first(where: { $0.name == "code" })?.value {
                    callbackHandled = true
                    let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
                    decisionHandler(.cancel)
                    onCallback(code, state)
                    return
                }
                if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
                    callbackHandled = true
                    let desc = components?.queryItems?.first(where: { $0.name == "error_description" })?.value
                    decisionHandler(.cancel)
                    onError(desc ?? error)
                    return
                }
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            if !callbackHandled {
                onError(error.localizedDescription)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            if let failingUrl = (error as NSError).userInfo["NSErrorFailingURLKey"] as? URL,
               !callbackHandled {
                let components = URLComponents(url: failingUrl, resolvingAgainstBaseURL: false)
                if let code = components?.queryItems?.first(where: { $0.name == "code" })?.value {
                    callbackHandled = true
                    let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
                    onCallback(code, state)
                    return
                }
            }
            if !callbackHandled {
                onError(error.localizedDescription)
            }
        }
    }
}
