import Foundation
import SwiftUI

/// Owns the playback queue and drives the audio engine. The UI talks only to
/// this object; it never touches AVPlayer or InnerTube directly.
@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?
    /// Dominant tint of the current track's artwork, for the ambient background.
    @Published private(set) var artworkColor: Color?
    private var colorTrackId: String?

    var currentTrack: Track? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    private let engine: AudioEngine
    private let nowPlaying = NowPlayingCenter()

    init(engine: AudioEngine) {
        self.engine = engine
        self.engine.onProgress = { [weak self] cur, dur in
            guard let self else { return }
            self.currentTime = cur
            if dur > 0 { self.duration = dur }
            if cur > 0 { self.isLoading = false }  // audio has actually started
        }
        self.engine.onEnded = { [weak self] in
            guard let self else { return }
            if self.hasNext {
                self.next()
            } else {
                // Last track finished — stop so YouTube Music's radio doesn't
                // silently take over playback behind our back.
                self.engine.pause()
                self.isPlaying = false
                self.pushNowPlaying()
            }
        }
        self.engine.onPlayingChanged = { [weak self] playing in
            guard let self, !self.isLoading else { return }
            self.isPlaying = playing
            self.pushNowPlaying()
        }

        // Route system media keys / Control Center into our queue.
        nowPlaying.onPlay = { [weak self] in self?.setPlaying(true) }
        nowPlaying.onPause = { [weak self] in self?.setPlaying(false) }
        nowPlaying.onToggle = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.next() }
        nowPlaying.onPrevious = { [weak self] in self?.previous() }
    }

    /// The videoId currently loaded into the engine, or nil if the selected
    /// track has only been cued (shown in the UI) but never started playing.
    private var loadedTrackId: String?

    private var hasNext: Bool {
        guard let i = currentIndex else { return false }
        return i + 1 < queue.count
    }

    // MARK: - Commands

    /// Plays `track`, using `context` as the surrounding queue (so next/prev work).
    func play(_ track: Track, in context: [Track]) {
        queue = context
        currentIndex = context.firstIndex(of: track) ?? 0
        startCurrent()
    }

    /// Keeps playback in sync with the current liked-songs list — called whenever
    /// the library changes (launch, refresh, unlike, pagination). Tracks no longer
    /// liked are dropped from the queue; if the *current* track was removed it
    /// advances to the next surviving track (or stops). While idle it also
    /// pre-selects the first track (shown paused, engine not booted).
    func reconcile(with tracks: [Track]) {
        let liveIds = Set(tracks.map(\.id))

        // Idle (cued on launch, nothing started): mirror the library exactly.
        if loadedTrackId == nil, !isPlaying {
            queue = tracks
            currentIndex = tracks.isEmpty ? nil : 0
            pushNowPlaying()
            return
        }

        guard let current = currentTrack else {
            queue = tracks
            currentIndex = tracks.isEmpty ? nil : 0
            return
        }

        // Current track was removed/unliked → advance to the next surviving one.
        if !liveIds.contains(current.id) {
            let oldIndex = currentIndex ?? 0
            let nextSurvivor = queue.dropFirst(oldIndex + 1).first { liveIds.contains($0.id) }
            queue = queue.filter { liveIds.contains($0.id) }
            if let nextSurvivor, let ni = queue.firstIndex(of: nextSurvivor) {
                currentIndex = ni
                let wasPlaying = isPlaying
                loadedTrackId = nil
                if wasPlaying { startCurrent() } else { pushNowPlaying() }
            } else {
                currentIndex = queue.isEmpty ? nil : min(oldIndex, queue.count - 1)
                engine.pause()
                isPlaying = false
                loadedTrackId = nil
                pushNowPlaying()
            }
            return
        }

        // Current still liked: just prune the other removed tracks from the queue.
        queue = queue.filter { liveIds.contains($0.id) }
        currentIndex = queue.firstIndex(of: current)
    }

    func togglePlayPause() {
        setPlaying(!isPlaying)
    }

    func setPlaying(_ playing: Bool) {
        guard let track = currentTrack else { return }
        if playing {
            // First play of a cued-but-not-loaded track boots the engine.
            if loadedTrackId != track.id {
                startCurrent()
                return
            }
            engine.play()
        } else {
            engine.pause()
        }
        isPlaying = playing
        pushNowPlaying()
    }

    func next() {
        guard let i = currentIndex, i + 1 < queue.count else { return }
        currentIndex = i + 1
        startCurrent()
    }

    func previous() {
        // Restart current track if we're past the first few seconds.
        if currentTime > 3 {
            engine.seek(to: 0)
            return
        }
        guard let i = currentIndex, i - 1 >= 0 else { return }
        currentIndex = i - 1
        startCurrent()
    }

    func seek(to seconds: Double) {
        engine.seek(to: seconds)
        currentTime = seconds
        pushNowPlaying()
    }

    // MARK: - Playback

    private func startCurrent() {
        guard let track = currentTrack else { return }
        currentTime = 0
        duration = Double(track.durationSeconds ?? 0)
        errorMessage = nil
        isLoading = true
        loadedTrackId = track.id
        engine.load(videoId: track.id)
        isPlaying = true
        pushNowPlaying()
    }

    private func pushNowPlaying() {
        nowPlaying.update(track: currentTrack,
                          isPlaying: isPlaying,
                          elapsed: currentTime,
                          duration: duration)
        refreshArtworkColor()
    }

    /// Recomputes the ambient tint only when the track actually changes.
    private func refreshArtworkColor() {
        let track = currentTrack
        guard track?.id != colorTrackId else { return }
        colorTrackId = track?.id

        guard let url = track?.thumbnailURL else {
            artworkColor = nil
            return
        }
        Task {
            let image = await ImageLoader.shared.image(for: url)
            guard colorTrackId == track?.id else { return }   // track changed meanwhile
            artworkColor = image.flatMap(ImageColor.dominant).map { Color(nsColor: $0) }
        }
    }
}
