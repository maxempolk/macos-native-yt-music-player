import Foundation

/// Extracts playable tracks from a `FEmusic_new_releases` browse response.
/// The page is a grid of `musicTwoRowItemRenderer` (albums + singles/videos);
/// we keep the items that carry a `videoId` (directly playable), skipping
/// album-only entries that would need a second browse to resolve tracks.
enum NewReleasesParser {
    static func tracks(in json: [String: Any]) -> [Track] {
        let items = JSONDig.findAll(key: "musicTwoRowItemRenderer", in: json)
        var seen = Set<String>()
        var result: [Track] = []

        for wrapper in items {
            guard let item = wrapper["musicTwoRowItemRenderer"] as? [String: Any],
                  let videoId = JSONDig.firstString(key: "videoId", in: item),
                  !seen.contains(videoId) else { continue }

            let title = runsText(item["title"]) ?? "Unknown"

            seen.insert(videoId)
            result.append(
                Track(id: videoId,
                      title: title,
                      artist: artist(in: item),
                      album: nil,
                      durationSeconds: nil,
                      thumbnailURL: thumbnailURL(in: item))
            )
        }
        return result
    }

    /// The artist from a card's subtitle. Subtitle runs look like
    /// "Single • Artist • 2026"; the artist run(s) carry a navigationEndpoint,
    /// while "Single"/"EP"/"Album"/year do not — so prefer linked runs.
    private static func artist(in item: [String: Any]) -> String {
        guard let runs = (item["subtitle"] as? [String: Any])?["runs"] as? [Any] else { return "" }

        let linked = runs.compactMap { r -> String? in
            guard let d = r as? [String: Any], d["navigationEndpoint"] != nil,
                  let t = d["text"] as? String else { return nil }
            return t
        }
        if !linked.isEmpty { return linked.joined() }

        // Fallback: drop type labels and years.
        let typeWords: Set<String> = ["single", "ep", "album", "video", "song"]
        let kept = runs
            .compactMap { ($0 as? [String: Any])?["text"] as? String }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "•" && Int($0) == nil && !typeWords.contains($0.lowercased()) }
        return kept.joined()
    }

    private static func runsText(_ any: Any?) -> String? {
        guard let runs = (any as? [String: Any])?["runs"] as? [Any] else { return nil }
        let text = runs.compactMap { ($0 as? [String: Any])?["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    private static func thumbnailURL(in item: [String: Any]) -> URL? {
        guard let thumbs = JSONDig.firstValue(key: "thumbnails", in: item) as? [Any],
              let last = thumbs.last as? [String: Any],
              let urlString = last["url"] as? String else { return nil }
        return URL(string: urlString)
    }
}
