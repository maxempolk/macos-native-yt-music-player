import SwiftUI
import WebKit

/// A one-time login sheet. Loads YouTube Music in a WebView, lets the user
/// sign in normally, then harvests the session cookies and hands them back.
/// After this completes the WebView is never shown again.
struct LoginWebView: NSViewRepresentable {
    /// Called once a YouTube Music session (with SAPISID) is detected.
    var onCookies: ([HTTPCookie]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCookies: onCookies) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // A desktop UA keeps Google's login flow on the standard path.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: URL(string: "https://music.youtube.com")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCookies: ([HTTPCookie]) -> Void
        private var finished = false

        init(onCookies: @escaping ([HTTPCookie]) -> Void) { self.onCookies = onCookies }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies(webView)
        }

        /// Capture only once the *YouTube* session is fully established. The
        /// google.com auth step sets SAPISID early, but music.youtube.com only
        /// issues LOGIN_INFO (the definitive YouTube login cookie) after the
        /// sign-in handshake completes. Grabbing earlier yields a half-session
        /// that the server still treats as logged-out.
        private func checkCookies(_ webView: WKWebView) {
            guard !finished else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let relevant = cookies.filter {
                    $0.domain.contains("youtube.com") || $0.domain.contains("google.com")
                }
                let hasYouTubeLogin = relevant.contains { $0.name == "LOGIN_INFO" }
                let hasAPISID = relevant.contains {
                    $0.name == "SAPISID" || $0.name == "__Secure-3PAPISID"
                }
                guard hasYouTubeLogin && hasAPISID else {
                    // Not ready yet — re-check shortly in case cookies land
                    // without another navigation event firing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak webView] in
                        guard let webView else { return }
                        self?.checkCookies(webView)
                    }
                    return
                }
                self.finished = true
                self.onCookies(relevant)
            }
        }
    }
}

/// Wraps the WebView in a sheet with a title bar and cancel control.
struct LoginSheet: View {
    @EnvironmentObject var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to YouTube Music")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(12)
            Divider()
            LoginWebView { cookies in
                Task { @MainActor in
                    session.update(cookies: cookies)
                    dismiss()
                }
            }
        }
        .frame(width: 520, height: 640)
    }
}
