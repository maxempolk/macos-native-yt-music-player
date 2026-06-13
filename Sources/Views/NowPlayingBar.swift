import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerController

    // Local scrub state so dragging the scrubber is instant and we seek only
    // once on release (no per-pixel JS round-trips fighting the position poll).
    @State private var scrubbing = false
    @State private var scrubValue = 0.0

    var body: some View {
        VStack(spacing: 8) {
            topRow
            progress
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(panelGlass, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.6), value: player.artworkColor)
    }

    /// Tints the panel's glass with the current track's artwork color — kept
    /// gentle (reduced opacity) so it suggests the color rather than painting it.
    private var panelGlass: Glass {
        player.artworkColor.map { Glass.regular.tint($0.opacity(0.4)) } ?? .regular
    }

    // Track info on the left, transport controls always pinned to the right.
    private var topRow: some View {
        HStack(spacing: 12) {
            trackInfo.frame(maxWidth: .infinity, alignment: .leading)
            controls.fixedSize()
        }
        .frame(height: 42)
    }

    private var trackInfo: some View {
        HStack(spacing: 10) {
            CachedImage(url: player.currentTrack?.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? "Not playing")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(player.currentTrack?.artist ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
            }
            ZStack {
                if player.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                }
            }
            .frame(width: 40, height: 40)
            .glassEffect(.regular.interactive(), in: Circle())
            Button { player.next() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .font(.title3)
        .disabled(player.currentTrack == nil)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            Text(timeText(scrubbing ? scrubValue : player.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : player.currentTime },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = player.currentTime
                        scrubbing = true
                    } else {
                        scrubbing = false
                        player.seek(to: scrubValue)
                    }
                }
            )
            .disabled(player.currentTrack == nil)
            Text(timeText(player.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
