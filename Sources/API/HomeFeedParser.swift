import Foundation

/// Parses the personalized home feed (`FEmusic_home`) into shelves, mirroring
/// YouTube Music's own rows. Each `musicCarouselShelfRenderer` becomes a `Shelf`
/// with its real title and the directly-playable tracks inside it.
enum HomeFeedParser {
    static func shelves(in json: [String: Any]) -> [Shelf] {
        let carousels = JSONDig.findAll(key: "musicCarouselShelfRenderer", in: json)
        var result: [Shelf] = []

        for (index, wrapper) in carousels.enumerated() {
            guard let shelf = wrapper["musicCarouselShelfRenderer"] as? [String: Any] else { continue }

            var seen = Set<String>()
            var items: [Track] = []
            // Song rows and cards that carry a direct videoId.
            for t in TrackParser.tracks(in: shelf) where seen.insert(t.id).inserted { items.append(t) }
            for t in NewReleasesParser.tracks(in: shelf) where seen.insert(t.id).inserted { items.append(t) }
            guard !items.isEmpty else { continue }

            let title = carouselTitle(shelf) ?? "Для вас"
            result.append(Shelf(id: "home-\(index)-\(title)", title: title, items: items))
        }
        return result
    }

    private static func carouselTitle(_ shelf: [String: Any]) -> String? {
        guard let header = JSONDig.firstValue(key: "musicCarouselShelfBasicHeaderRenderer", in: shelf) as? [String: Any],
              let runs = (header["title"] as? [String: Any])?["runs"] as? [Any],
              let text = (runs.first as? [String: Any])?["text"] as? String,
              !text.isEmpty else { return nil }
        return text
    }
}
