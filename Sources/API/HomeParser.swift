import Foundation

/// Extracts playable tracks from the personalized home feed (`FEmusic_home`):
/// song rows (`musicResponsiveListItemRenderer`, e.g. Quick Picks) plus cards
/// (`musicTwoRowItemRenderer`) that carry a `videoId`. Albums/playlists without
/// a direct videoId are skipped. Deduplicated, original order preserved.
enum HomeParser {
    static func tracks(in json: [String: Any]) -> [Track] {
        var seen = Set<String>()
        var result: [Track] = []

        func add(_ tracks: [Track]) {
            for t in tracks where !seen.contains(t.id) {
                seen.insert(t.id)
                result.append(t)
            }
        }

        add(TrackParser.tracks(in: json))      // song rows (quick picks, etc.)
        add(NewReleasesParser.tracks(in: json)) // cards with a direct videoId
        return result
    }
}
