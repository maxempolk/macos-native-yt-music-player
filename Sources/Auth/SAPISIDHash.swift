import Foundation
import CryptoKit

/// Builds the `Authorization` header Google's internal APIs expect when
/// authenticating with cookies.
///
/// Each component is `<SCHEME> <unix_ts>_<sha1hex("<ts> <SID_VALUE> <origin>")>`.
/// Modern music.youtube.com expects all three schemes when the corresponding
/// cookies are present:
///   SAPISIDHASH   ← SAPISID
///   SAPISID1PHASH ← __Secure-1PAPISID
///   SAPISID3PHASH ← __Secure-3PAPISID
enum SAPISIDHash {
    static let origin = "https://music.youtube.com"

    private static func hash(_ value: String, ts: Int) -> String {
        let payload = "\(ts) \(value) \(origin)"
        let digest = Insecure.SHA1.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Combined Authorization header value, or nil if no usable cookie is present.
    static func authorization(sapisid: String?,
                              sapisid1p: String?,
                              sapisid3p: String?,
                              now: Date = Date()) -> String? {
        let ts = Int(now.timeIntervalSince1970)
        var parts: [String] = []
        if let s = sapisid { parts.append("SAPISIDHASH \(ts)_\(hash(s, ts: ts))") }
        if let s = sapisid1p { parts.append("SAPISID1PHASH \(ts)_\(hash(s, ts: ts))") }
        if let s = sapisid3p { parts.append("SAPISID3PHASH \(ts)_\(hash(s, ts: ts))") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
