import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var player: PlayerController

    var body: some View {
        VStack(spacing: 10) {
            topRow
            ProgressBar(
                elapsed: player.currentTime,
                duration: totalDuration,
                enabled: player.currentTrack != nil,
                onScrub: { player.seek(to: $0) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 7)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// Falls back to the track's own length so the bar never shows 0:00 on the
    /// right before playback has actually started.
    private var totalDuration: Double {
        player.duration > 0 ? player.duration : Double(player.currentTrack?.durationSeconds ?? 0)
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? "Not playing")
                    .font(.system(.body, design: .default).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                ArtistLabel(text: player.currentTrack?.artist ?? "",
                            font: .subheadline, color: .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Fixed size so the text column never pushes or squeezes the buttons.
            transport.fixedSize()
        }
        .frame(height: 46)
    }

    private var artwork: some View {
        CachedImage(url: player.currentTrack?.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary)
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                player.showLyrics.toggle()
            }
            .help("Lyrics")

            plainIcon("backward.fill") { player.previous() }

            playButton

            plainIcon("forward.fill") { player.next() }
        }
        .disabled(player.currentTrack == nil)
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
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

/// A thin, gradient progress bar with a thumb that appears on hover and can be
/// dragged to scrub. Seeks once on release.
private struct ProgressBar: View {
    let elapsed: Double
    let duration: Double
    let enabled: Bool
    let onScrub: (Double) -> Void

    @State private var hovering = false
    @State private var dragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 5) {
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

            HStack {
                Text(timeText(dragging ? dragValue : elapsed))
                Spacer()
                Text(timeText(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
