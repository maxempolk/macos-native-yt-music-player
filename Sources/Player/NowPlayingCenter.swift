import Foundation
import MediaPlayer
import AppKit

/// Bridges playback to the system: publishes Now Playing info (Control Center,
/// lock screen, menu bar) and routes hardware/Control Center media keys back
/// into the app. Our app — not the hidden web player — owns these.
@MainActor
final class NowPlayingCenter {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    private var artworkURL: URL?   // guards against stale async artwork writes

    init() {
        configureCommands()
    }

    /// Pushes the current track + playback state to the system.
    func update(track: Track?, isPlaying: Bool, elapsed: Double, duration: Double) {
        let center = MPNowPlayingInfoCenter.default()

        guard let track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            artworkURL = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }

        // Keep any artwork already attached for this same track.
        if let existing = center.nowPlayingInfo?[MPMediaItemPropertyArtwork], artworkURL == track.thumbnailURL {
            info[MPMediaItemPropertyArtwork] = existing
        }

        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused

        loadArtworkIfNeeded(for: track)
    }

    // MARK: - Artwork

    private func loadArtworkIfNeeded(for track: Track) {
        guard let url = track.thumbnailURL, url != artworkURL else { return }
        artworkURL = url
        Task {
            guard let image = await ImageLoader.shared.image(for: url) else { return }
            // Drop if the track changed while we were loading.
            guard self.artworkURL == url else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    // MARK: - Remote commands

    private func configureCommands() {
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.addTarget { [weak self] _ in self?.onPlay?(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.onPause?(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.onToggle?(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.onNext?(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.onPrevious?(); return .success }

        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        // We handle seeking inside the app, not via the remote scrubber for now.
        c.changePlaybackPositionCommand.isEnabled = false
    }
}
