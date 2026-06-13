import Foundation

/// Holds the authenticated YouTube Music session (cookies) and exposes the
/// headers InnerTube requests need. Persisted in the Keychain.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var isAuthenticated: Bool

    /// Raw `Cookie:` header value, e.g. "SAPISID=...; __Secure-3PAPISID=...; ...".
    private(set) var cookieHeader: String?
    /// Parsed cookie name -> value (last write wins on duplicate names).
    private var cookieMap: [String: String] = [:]

    private static let cookieAccount = "cookie-header"

    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init() {
        let stored = Keychain.get(Self.cookieAccount)
        self.cookieHeader = stored
        self.cookieMap = stored.map(Self.parse) ?? [:]
        self.isAuthenticated = Self.hasSession(in: self.cookieMap)
    }

    /// Called by the login flow once cookies have been captured.
    func update(cookies: [HTTPCookie]) {
        // Deduplicate by name; prefer youtube.com-scoped values when names clash.
        var map: [String: String] = [:]
        for c in cookies.sorted(by: { !$0.domain.contains("youtube") && $1.domain.contains("youtube") }) {
            map[c.name] = c.value
        }
        let header = map.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        guard Self.hasSession(in: map), !header.isEmpty else { return }

        self.cookieMap = map
        self.cookieHeader = header
        self.isAuthenticated = true
        Keychain.set(header, for: Self.cookieAccount)
    }

    func signOut() {
        cookieHeader = nil
        cookieMap = [:]
        isAuthenticated = false
        Keychain.delete(Self.cookieAccount)
    }

    /// Headers common to every authenticated InnerTube call.
    func authHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if let cookieHeader { headers["Cookie"] = cookieHeader }
        if let auth = SAPISIDHash.authorization(
            sapisid: cookieMap["SAPISID"] ?? cookieMap["__Secure-3PAPISID"],
            sapisid1p: cookieMap["__Secure-1PAPISID"],
            sapisid3p: cookieMap["__Secure-3PAPISID"]
        ) {
            headers["Authorization"] = auth
        }
        headers["X-Goog-AuthUser"] = "0"
        headers["Origin"] = SAPISIDHash.origin
        headers["Referer"] = SAPISIDHash.origin + "/"
        headers["User-Agent"] = Self.browserUserAgent
        return headers
    }

    // MARK: - Helpers

    private static func parse(_ header: String) -> [String: String] {
        var map: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let kv = pair.trimmingCharacters(in: .whitespaces)
                .split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { map[kv[0]] = kv[1] }
        }
        return map
    }

    /// True when the cookie set carries an authenticated YouTube session.
    /// LOGIN_INFO is the cookie music.youtube.com actually checks for login.
    private static func hasSession(in map: [String: String]) -> Bool {
        let hasAPISID = map["SAPISID"] != nil || map["__Secure-3PAPISID"] != nil
        return hasAPISID && map["LOGIN_INFO"] != nil
    }
}
