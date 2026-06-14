import Foundation

/// One line of lyrics. For synced lyrics `time` is its start (seconds); for
/// plain lyrics `time` is unused.
struct LyricLine: Identifiable, Sendable {
    let id: Int
    let time: Double
    let text: String
}

/// Parsed lyrics for a track.
struct LyricsResult: Sendable {
    let lines: [LyricLine]
    let synced: Bool
    let instrumental: Bool

    var isEmpty: Bool { lines.isEmpty && !instrumental }
}

/// Fetches lyrics from LRCLIB (lrclib.net) — a free, no-auth, open lyrics API
/// that returns both synced (LRC) and plain lyrics.
enum LyricsService {
    private static let session = URLSession(configuration: .default)
    private static let userAgent =
        "Tune (https://github.com/maxempolk/macos-native-yt-music-player)"

    private struct Item: Codable {
        var trackName: String?
        var artistName: String?
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    static func fetch(artist: String, title: String, duration: Int?) async -> LyricsResult? {
        // Exact match first (most accurate), then a looser search.
        if let item = await getExact(artist: artist, title: title, duration: duration) {
            return result(from: item)
        }
        if let item = await search(artist: artist, title: title, duration: duration) {
            return result(from: item)
        }
        return nil
    }

    // MARK: - Endpoints

    private static func getExact(artist: String, title: String, duration: Int?) async -> Item? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var q = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
        ]
        if let duration { q.append(URLQueryItem(name: "duration", value: String(duration))) }
        comps.queryItems = q
        return await decode(Item.self, from: comps.url)
    }

    private static func search(artist: String, title: String, duration: Int?) async -> Item? {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let items = await decode([Item].self, from: comps.url), !items.isEmpty else {
            return nil
        }
        // Prefer synced, then closest duration to ours.
        func closeness(_ i: Item) -> Double {
            guard let d = duration, let id = i.duration else { return .greatestFiniteMagnitude }
            return abs(id - Double(d))
        }
        let synced = items.filter { ($0.syncedLyrics?.isEmpty == false) }
        if let best = synced.min(by: { closeness($0) < closeness($1) }) { return best }
        let plain = items.filter { ($0.plainLyrics?.isEmpty == false) }
        if let best = plain.min(by: { closeness($0) < closeness($1) }) { return best }
        return items.first
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL?) async -> T? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Build result

    private static func result(from item: Item) -> LyricsResult {
        if item.instrumental == true {
            return LyricsResult(lines: [], synced: false, instrumental: true)
        }
        if let lrc = item.syncedLyrics, !lrc.isEmpty {
            let lines = LRCParser.parse(lrc)
            if !lines.isEmpty {
                return LyricsResult(lines: lines, synced: true, instrumental: false)
            }
        }
        if let plain = item.plainLyrics, !plain.isEmpty {
            let lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { LyricLine(id: $0.offset, time: 0, text: String($0.element)) }
            return LyricsResult(lines: lines, synced: false, instrumental: false)
        }
        return LyricsResult(lines: [], synced: false, instrumental: false)
    }
}

/// Parses LRC timestamps `[mm:ss.xx]` into time-ordered lines.
enum LRCParser {
    private static let regex = try! NSRegularExpression(
        pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var collected: [(Double, String)] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty, let last = matches.last else { continue }

            // Text is everything after the final timestamp.
            let textStart = last.range.location + last.range.length
            let text = ns.substring(from: textStart)
                .trimmingCharacters(in: .whitespaces)

            for m in matches {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                collected.append((mm * 60 + ss + frac, text))
            }
        }
        return collected
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
