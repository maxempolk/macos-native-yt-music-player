import Foundation

/// A single playable item from YouTube Music.
struct Track: Identifiable, Hashable, Sendable, Codable {
    let id: String          // videoId
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Int?
    let thumbnailURL: URL?

    var durationText: String {
        guard let s = durationSeconds else { return "" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
