import Foundation

/// Small helpers for spelunking through InnerTube's deeply-nested,
/// frequently-reshuffled JSON without hard-coding brittle paths.
enum JSONDig {
    /// Depth-first search returning every dictionary that contains `key`.
    static func findAll(key: String, in any: Any) -> [[String: Any]] {
        var out: [[String: Any]] = []
        walk(any) { dict in
            if dict[key] != nil { out.append(dict) }
        }
        return out
    }

    /// First value found for `key` anywhere under `any`.
    static func firstValue(key: String, in any: Any) -> Any? {
        var found: Any?
        walk(any) { dict in
            if found == nil, let v = dict[key] { found = v }
        }
        return found
    }

    /// First string found for `key` anywhere under `any`.
    static func firstString(key: String, in any: Any) -> String? {
        firstValue(key: key, in: any) as? String
    }

    private static func walk(_ any: Any, _ visit: ([String: Any]) -> Void) {
        if let dict = any as? [String: Any] {
            visit(dict)
            for v in dict.values { walk(v, visit) }
        } else if let arr = any as? [Any] {
            for v in arr { walk(v, visit) }
        }
    }
}
