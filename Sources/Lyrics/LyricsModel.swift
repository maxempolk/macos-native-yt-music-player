import Foundation

@MainActor
final class LyricsModel: ObservableObject {
    enum State { case idle, loading, loaded, empty, instrumental }

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var synced = false
    @Published private(set) var state: State = .idle

    private var loadedTrackId: String?
    private var cache: [String: LyricsResult] = [:]

    /// Loads lyrics for the given track (cached per track id).
    func load(for track: Track?) async {
        guard let track else {
            apply(nil); loadedTrackId = nil; return
        }
        if loadedTrackId == track.id, state != .idle { return }   // already shown
        loadedTrackId = track.id

        if let cached = cache[track.id] {
            apply(cached); return
        }

        state = .loading
        let result = await LyricsService.fetch(artist: track.artist,
                                               title: track.title,
                                               duration: track.durationSeconds)
        guard loadedTrackId == track.id else { return }   // track changed mid-fetch
        if let result { cache[track.id] = result }
        apply(result)
    }

    /// Index of the line currently being sung, for `time` (synced only).
    func currentIndex(at time: Double) -> Int? {
        guard synced else { return nil }
        var idx: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= time { idx = i } else { break }
        }
        return idx
    }

    private func apply(_ result: LyricsResult?) {
        guard let result else {
            lines = []; synced = false; state = .empty; return
        }
        lines = result.lines
        synced = result.synced
        if result.instrumental {
            state = .instrumental
        } else {
            state = result.lines.isEmpty ? .empty : .loaded
        }
    }
}
