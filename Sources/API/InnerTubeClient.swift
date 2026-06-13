import Foundation

enum InnerTubeError: LocalizedError {
    case notAuthenticated
    case badResponse(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to YouTube Music."
        case .badResponse(let code): return "YouTube returned HTTP \(code)."
        case .decoding: return "Could not parse YouTube's response."
        }
    }
}

/// Talks to YouTube Music's internal `youtubei/v1` API for library data.
/// Uses the WEB_REMIX client with the user's cookies + SAPISIDHASH auth.
/// (Audio playback is handled separately by `WebViewAudioEngine`.)
@MainActor
struct InnerTubeClient {
    let session: SessionStore

    private let base = "https://music.youtube.com/youtubei/v1"
    private let webKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    /// Dedicated session with cookie handling OFF so our manually-set `Cookie`
    /// header is sent verbatim. `URLSession.shared` would otherwise override it
    /// with its own (empty) cookie jar and the request goes out logged-out.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    /// Fetches the user's full "Liked Music" playlist, following continuation
    /// tokens to load every page (not just the first ~100). `onPage` is called
    /// with the cumulative list after each page so the UI can fill in live.
    func likedSongs(onPage: (([Track]) -> Void)? = nil) async throws -> [Track] {
        guard session.isAuthenticated else { throw InnerTubeError.notAuthenticated }

        var all: [Track] = []
        var seen = Set<String>()
        func absorb(_ page: [Track]) {
            for t in page where !seen.contains(t.id) {
                seen.insert(t.id)
                all.append(t)
            }
        }

        var json = try await post("browse", body: [
            "context": webContext(),
            "browseId": "FEmusic_liked_videos",
        ])
        absorb(TrackParser.tracks(in: json))
        onPage?(all)

        var token = ContinuationParser.token(in: json)
        var pages = 0
        while let t = token, pages < 100 {   // safety cap against runaway loops
            pages += 1
            json = try await post("browse", body: [
                "context": webContext(),
                "continuation": t,
            ])
            let before = all.count
            absorb(TrackParser.tracks(in: json))
            onPage?(all)
            token = ContinuationParser.token(in: json)
            if all.count == before { break }  // no new tracks -> stop
        }
        return all
    }

    /// Removes a song from "Liked Music" (resets its rating to indifferent).
    func removeLike(videoId: String) async throws {
        guard session.isAuthenticated else { throw InnerTubeError.notAuthenticated }
        _ = try await post("like/removelike", body: [
            "context": webContext(),
            "target": ["videoId": videoId],
        ])
    }

    // MARK: - Request plumbing

    private func post(_ endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        var comps = URLComponents(string: "\(base)/\(endpoint)")!
        comps.queryItems = [
            URLQueryItem(name: "key", value: webKey),
            URLQueryItem(name: "prettyPrint", value: "false"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in session.authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await Self.session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw InnerTubeError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw InnerTubeError.badResponse(http.statusCode)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InnerTubeError.decoding
        }
        return obj
    }

    private func webContext() -> [String: Any] {
        [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20240417.01.00",
                "hl": "en",
                "gl": "US",
            ]
        ]
    }
}
