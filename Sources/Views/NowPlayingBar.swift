import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerController

    /// Width the full bar caps at; beyond this it just centers in the window.
    private let maxBarWidth: CGFloat = 460

    private var hasTrack: Bool { player.currentTrack != nil }

    var body: some View {
        // Nothing is shown until a track is cued — the bar slides in on first
        // play and slides back out if the queue empties.
        Group {
            if hasTrack { fullBar }
        }
        .frame(maxWidth: maxBarWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: hasTrack)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Full bar (top row: metadata + transport · bottom: progress)

    private var fullBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Artwork + title/artist
                HStack(spacing: 10) {
                    artwork(size: 44, radius: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.currentTrack?.title ?? "Not playing")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        ArtistLabel(text: player.currentTrack?.artist ?? "",
                                    font: .caption, color: .secondary)
                    }
                    .frame(maxWidth: 170, alignment: .leading)
                    .fixedSize()
                }
                Spacer()
                transport.fixedSize()
            }

            ProgressBar(
                elapsed: player.currentTime,
                duration: totalDuration,
                enabled: player.currentTrack != nil,
                showTimes: true,
                onScrub: { player.seek(to: $0) }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 7)
    }

    // MARK: - Compact pill (artwork + play/pause + progress)

    /// Falls back to the track's own length so the bar never shows 0:00 on the
    /// right before playback has actually started.
    private var totalDuration: Double {
        player.duration > 0 ? player.duration : Double(player.currentTrack?.durationSeconds ?? 0)
    }

    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        CachedImage(url: player.currentTrack?.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .scaleEffect(player.isPlaying ? 1 : 0.93)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
        .id(player.currentTrack?.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.35), value: player.currentTrack?.id)
    }

    // MARK: - Transport cluster

    private var transport: some View {
        HStack(spacing: 14) {
            plainIcon("text.quote", active: player.showLyrics) {
                guard !player.lyricsTransitioning else { return }
                player.showLyrics.toggle()
            }
            .help("Lyrics")
            .disabled(player.lyricsTransitioning)

            plainIcon("backward.fill") { player.previous() }

            playButton

            plainIcon("forward.fill") { player.next() }
        }
        .disabled(player.currentTrack == nil)
    }

    private var playButton: some View {
        Button { player.togglePlayPause() } label: {
            ZStack {
                if player.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            // Equal width == height so the prominent glass renders a circle.
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.glassProminent)
        .clipShape(Circle())
    }

    /// Borderless icon button — no glass outline at rest.
    private func plainIcon(_ name: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.body)
                .foregroundStyle(active ? Color.accentColor : .primary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A thin, gradient progress bar with a thumb that appears on hover and can be
/// dragged to scrub. Seeks once on release. Times sit inline at the ends when
/// `showTimes` is set; the compact pill hides them.
private struct ProgressBar: View {
    let elapsed: Double
    let duration: Double
    let enabled: Bool
    let showTimes: Bool
    let onScrub: (Double) -> Void

    @State private var hovering = false
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            if showTimes {
                Text(timeText(dragging ? dragValue : elapsed))
                    .frame(width: 32, alignment: .leading)
            }
            track
            if showTimes {
                Text(timeText(duration))
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var track: some View {
        GeometryReader { geo in
            let total = max(duration, 1)
            let value = dragging ? dragValue : elapsed
            let frac = min(max(value / total, 0), 1)
            let w = geo.size.width

            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15)).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(
                        colors: [.primary.opacity(0.85), .primary.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, w * frac), height: 4)
                Circle()
                    .fill(.primary)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .offset(x: min(max(0, w * frac - 5.5), w - 11))
                    .opacity(hovering || dragging ? 1 : 0)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        dragging = true
                        dragValue = min(max(g.location.x / w, 0), 1) * total
                    }
                    .onEnded { _ in
                        onScrub(dragValue)
                        dragging = false
                    }
            )
            .onHover { hovering = $0 }
        }
        .frame(height: 14)
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
