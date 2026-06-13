import Foundation

/// Extracts `Track`s out of a `browse` response by locating every
/// `musicResponsiveListItemRenderer` and pulling its fields tolerantly.
enum TrackParser {
    static func tracks(in json: [String: Any]) -> [Track] {
        let items = JSONDig.findAll(key: "musicResponsiveListItemRenderer", in: json)
        var seen = Set<String>()
        var result: [Track] = []

        for wrapper in items {
            guard let item = wrapper["musicResponsiveListItemRenderer"] as? [String: Any],
                  let videoId = videoId(in: item),
                  !seen.contains(videoId) else { continue }

            let columns = flexColumnTexts(in: item)
            let title = columns.first ?? "Unknown"
            // Columns after the title are artist / album / etc; the first is the artist.
            let artist = columns.count > 1 ? columns[1] : ""
            let album = columns.count > 2 ? columns[2] : nil

            seen.insert(videoId)
            result.append(
                Track(
                    id: videoId,
                    title: title,
                    artist: artist,
                    album: album,
                    durationSeconds: durationSeconds(in: item),
                    thumbnailURL: thumbnailURL(in: item)
                )
            )
        }
        return result
    }

    // MARK: - Field extraction

    private static func videoId(in item: [String: Any]) -> String? {
        if let playlistData = item["playlistItemData"] as? [String: Any],
           let vid = playlistData["videoId"] as? String {
            return vid
        }
        // Fall back to any watchEndpoint videoId nested in the item.
        return JSONDig.firstString(key: "videoId", in: item)
    }

    /// The first run of text out of each flex column (title, artist, ...).
    private static func flexColumnTexts(in item: [String: Any]) -> [String] {
        guard let cols = item["flexColumns"] as? [Any] else { return [] }
        return cols.compactMap { col -> String? in
            guard let renderer = JSONDig.firstValue(
                    key: "text", in: col) as? [String: Any],
                  let runs = renderer["runs"] as? [Any] else { return nil }
            let text = runs.compactMap { ($0 as? [String: Any])?["text"] as? String }
                .joined()
            return text.isEmpty ? nil : text
        }
    }

    private static func thumbnailURL(in item: [String: Any]) -> URL? {
        guard let thumbs = JSONDig.firstValue(key: "thumbnails", in: item) as? [Any],
              let last = thumbs.last as? [String: Any],
              let urlString = last["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    private static func durationSeconds(in item: [String: Any]) -> Int? {
        // Look for "m:ss" style text in fixed columns / accessibility labels.
        guard let fixed = item["fixedColumns"] as? [Any] else { return nil }
        for col in fixed {
            guard let renderer = JSONDig.firstValue(key: "text", in: col) as? [String: Any],
                  let runs = renderer["runs"] as? [Any],
                  let text = (runs.first as? [String: Any])?["text"] as? String else { continue }
            if let s = parseDuration(text) { return s }
        }
        return nil
    }

    private static func parseDuration(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
