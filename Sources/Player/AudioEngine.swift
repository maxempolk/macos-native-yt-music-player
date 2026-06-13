import Foundation

/// Abstraction over "the thing that actually makes sound", so the native
/// AVPlayer engine can later be swapped for a hidden audio WebView (or any
/// other backend) without touching the UI or the player controller.
@MainActor
protocol AudioEngine: AnyObject {
    /// Loads a track by its YouTube videoId and begins playback.
    func load(videoId: String)
    func play()
    func pause()
    func seek(to seconds: Double)

    /// current time, total duration (seconds). Fired periodically.
    var onProgress: ((Double, Double) -> Void)? { get set }
    /// Fired when the current item finishes naturally.
    var onEnded: (() -> Void)? { get set }
    /// Fired when the underlying player's play/pause state actually changes
    /// (true = playing, false = paused), so the UI reflects reality rather than
    /// our optimistic guess.
    var onPlayingChanged: ((Bool) -> Void)? { get set }
}
