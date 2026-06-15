import Foundation

/// Recently-played history, persisted as JSON in Application Support (survives
/// app restarts and cache purges). Deduplicated per track, most-recent-first.
@MainActor
final class PlayHistoryStore: ObservableObject {
    struct Entry: Codable, Identifiable {
        let track: Track
        var lastPlayedAt: Date
        var playCount: Int
        var id: String { track.id }
    }

    /// A track only counts once it has actually played past this many seconds —
    /// keeps seeks / accidental taps out of history.
    static let qualifyThreshold: TimeInterval = 10

    private let limit = 50

    @Published private(set) var entries: [Entry] = []

    /// Tracks for the "Recent" section (already most-recent-first, deduplicated).
    var recentTracks: [Track] { entries.map(\.track) }

    init() { load() }

    /// Records a play (call once the qualify threshold is crossed).
    func record(_ track: Track) {
        if let idx = entries.firstIndex(where: { $0.track.id == track.id }) {
            var e = entries.remove(at: idx)
            e.lastPlayedAt = Date()
            e.playCount += 1
            entries.insert(e, at: 0)
        } else {
            entries.insert(Entry(track: track, lastPlayedAt: Date(), playCount: 1), at: 0)
        }
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
        save()
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.maksym.tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
