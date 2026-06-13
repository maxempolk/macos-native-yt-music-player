import Foundation

/// Extracts the "load more" continuation token from a browse response, so we
/// can page through the entire liked-songs list instead of just the first page.
enum ContinuationParser {
    static func token(in json: [String: Any]) -> String? {
        // Modern youtubei: continuationItemRenderer -> continuationEndpoint
        //                  -> continuationCommand.token
        if let cmd = JSONDig.firstValue(key: "continuationCommand", in: json) as? [String: Any],
           let token = cmd["token"] as? String, !token.isEmpty {
            return token
        }
        // Legacy: continuations[].nextContinuationData.continuation
        if let data = JSONDig.firstValue(key: "nextContinuationData", in: json) as? [String: Any],
           let token = data["continuation"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }
}
