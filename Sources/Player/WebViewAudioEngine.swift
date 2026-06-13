import Foundation
import WebKit
import AppKit

/// Plays audio by driving the real YouTube Music web player inside a hidden,
/// off-screen WKWebView. Shares the logged-in session (cookies) with the login
/// flow, so Premium quality + no ads + every track is playable, and we never
/// have to decode YouTube's signature cipher.
///
/// The window is invisible (zero-size, behind everything); the native SwiftUI
/// UI is unaffected. We control the page's `<video>` element via injected JS
/// and receive progress/ended events back through a script message handler.
@MainActor
final class WebViewAudioEngine: NSObject, AudioEngine, WKScriptMessageHandler, WKNavigationDelegate {
    var onProgress: ((Double, Double) -> Void)?
    var onEnded: (() -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?

    private var webView: WKWebView!
    private var attached = false
    private var lastPaused: Bool?           // to fire onPlayingChanged only on change
    private var expectedVideoId: String?    // what we last asked the player to play
    private var handledDivergenceId: String? // foreign videoId we already reacted to
    private var endedForId: String?         // expected id we already fired clean-end for
    /// True once the watch page has loaded at least once, so the in-page
    /// player (`#movie_player`) exists and we can switch tracks via its JS API
    /// instead of reloading the whole page.
    private var hasBooted = false

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                 // shared login session
        config.mediaTypesRequiringUserActionForPlayback = [] // allow autoplay

        let controller = WKUserContentController()
        controller.add(self, name: "tune")
        controller.addUserScript(WKUserScript(source: Self.bridgeJS,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        config.userContentController = controller
        Self.installContentBlocking(into: controller)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    /// Blocks images and fonts in the hidden player — they're pure overhead for
    /// audio-only playback and are a big chunk of the WebView's memory. Compiles
    /// once at startup; ready well before the user triggers the first track.
    private static func installContentBlocking(into controller: WKUserContentController) {
        let rules = """
        [
          {"trigger":{"url-filter":".*","resource-type":["image"]},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*","resource-type":["font"]},"action":{"type":"block"}}
        ]
        """
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "tune-audio-only",
            encodedContentRuleList: rules
        ) { list, _ in
            guard let list else { return }
            Task { @MainActor in controller.add(list) }
        }
    }

    // MARK: - AudioEngine

    func load(videoId: String) {
        attachIfNeeded()
        lastPaused = nil           // let the new track report its initial state fresh
        expectedVideoId = videoId
        endedForId = nil
        // Keep handledDivergenceId so we don't re-fire for the radio pick we're
        // currently overriding; it's cleared once the player reaches our track.
        guard hasBooted else {
            // First track: full navigation boots the in-page player.
            navigate(to: videoId)
            return
        }
        // Subsequent tracks: switch in-place via the SPA player. If the player
        // isn't actually ready, fall back to a full navigation.
        webView.evaluateJavaScript("window.__tuneLoad ? __tuneLoad('\(videoId)') : false") { result, _ in
            let switched = (result as? Bool) ?? false
            if !switched {
                Task { @MainActor in self.navigate(to: videoId) }
            }
        }
    }

    private func navigate(to videoId: String) {
        let url = URL(string: "https://music.youtube.com/watch?v=\(videoId)")!
        webView.load(URLRequest(url: url))
    }

    func play()  { evaluate("window.__tunePlay && __tunePlay()") }
    func pause() { evaluate("window.__tunePause && __tunePause()") }
    func seek(to seconds: Double) { evaluate("window.__tuneSeek && __tuneSeek(\(seconds))") }

    // MARK: - Navigation

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.hasBooted = true }
    }

    // MARK: - JS bridge messages

    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        Task { @MainActor in
            guard type == "progress" else { return }
            let t = body["t"] as? Double ?? 0
            let d = body["d"] as? Double ?? 0
            let state = body["state"] as? Int ?? -1
            let videoId = body["videoId"] as? String ?? ""

            self.onProgress?(t, d)

            if let paused = body["paused"] as? Bool, paused != self.lastPaused {
                self.lastPaused = paused
                self.onPlayingChanged?(!paused)
            }

            self.detectTrackEnd(state: state, videoId: videoId)
        }
    }

    /// Decides when the current track has ended — either cleanly (player reports
    /// ENDED on the same video) or because YouTube Music silently auto-advanced
    /// its radio to a different video. Either way we fire `onEnded` exactly once
    /// so the controller drives our own queue.
    private func detectTrackEnd(state: Int, videoId: String) {
        // Player has reached the track we asked for: transition is complete.
        if !videoId.isEmpty, videoId == expectedVideoId {
            handledDivergenceId = nil
        }

        // Auto-advance: the player is on a video we didn't request.
        if !videoId.isEmpty, let expected = expectedVideoId,
           videoId != expected, videoId != handledDivergenceId {
            handledDivergenceId = videoId
            onEnded?()
            return
        }

        // Clean end: ENDED state on the same video we asked for.
        if state == 0, let expected = expectedVideoId,
           videoId.isEmpty || videoId == expected, endedForId != expected {
            endedForId = expected
            onEnded?()
        }
    }

    // MARK: - Hidden hosting

    /// Attach the WebView to the key window as a 1×1 subview in the corner.
    /// It must stay *visible* (not hidden, non-zero size) or WebKit may throttle
    /// its timers and pause audio — but 1px is imperceptible to the user.
    private func attachIfNeeded() {
        guard !attached,
              let contentView = NSApp.keyWindow?.contentView ?? NSApp.windows.first?.contentView
        else { return }
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        webView.autoresizingMask = []
        contentView.addSubview(webView)
        attached = true
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Injected control script

    private static let bridgeJS = """
    (function () {
      function player() { return document.getElementById('movie_player'); }
      function vid() { return document.querySelector('video'); }
      function post(m) { try { window.webkit.messageHandlers.tune.postMessage(m); } catch (e) {} }

      // Neutralize the page's Media Session so the native app owns the system
      // Now Playing / media keys instead of this hidden web player.
      try {
        if (navigator.mediaSession) {
          navigator.mediaSession.setActionHandler = function () {};
          try { Object.defineProperty(navigator.mediaSession, 'metadata',
                  { configurable: true, set: function () {}, get: function () { return null; } }); } catch (e) {}
          try { Object.defineProperty(navigator.mediaSession, 'playbackState',
                  { configurable: true, set: function () {}, get: function () { return 'none'; } }); } catch (e) {}
        }
      } catch (e) {}

      window.__tunePlay  = function () { var v = vid(); if (v) v.play(); };
      window.__tunePause = function () { var v = vid(); if (v) v.pause(); };
      window.__tuneSeek  = function (s) {
        var p = player();
        if (p && typeof p.seekTo === 'function') { p.seekTo(s, true); return; }
        var v = vid(); if (v) v.currentTime = s;
      };

      // Switch track in-place using the in-page YouTube player API. Returns
      // false if the player isn't ready, so the app can fall back to a reload.
      window.__tuneLoad = function (id) {
        var p = player();
        if (p && typeof p.loadVideoById === 'function') { p.loadVideoById(id); return true; }
        return false;
      };

      // YouTube player states: -1 unstarted, 0 ended, 1 playing, 2 paused,
      // 3 buffering, 5 cued. We forward raw state + videoId; the app decides
      // when a track ended (incl. when YT silently auto-advances its radio).
      function tick() {
        var p = player();
        if (p && typeof p.getCurrentTime === 'function') {
          var st = (typeof p.getPlayerState === 'function') ? p.getPlayerState() : -1;
          var vidId = '';
          try { vidId = p.getVideoData ? (p.getVideoData().video_id || '') : ''; } catch (e) {}
          post({ type: 'progress', t: p.getCurrentTime() || 0, d: p.getDuration() || 0,
                 paused: st === 2, state: st, videoId: vidId });
        } else {
          var v = vid();
          if (!v) return;
          post({ type: 'progress', t: v.currentTime || 0, d: isFinite(v.duration) ? v.duration : 0,
                 paused: v.paused, state: (v.ended ? 0 : (v.paused ? 2 : 1)), videoId: '' });
        }
      }
      setInterval(tick, 250);
    })();
    """
}
