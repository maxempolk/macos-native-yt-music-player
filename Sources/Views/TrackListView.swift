import SwiftUI
import AppKit

/// Reusable track list used by every library section (Favorites / Recent / New).
/// The now-playing indicator depends on the player, so it works identically in
/// all sections. Pull-to-refresh and the remove action are optional per section.
struct TrackListView: View {
    let tracks: [Track]
    var isLoading: Bool = false
    var error: String? = nil

    let emptyTitle: String
    let emptyImage: String
    let emptyMessage: String

    var onRefresh: (() async -> Void)? = nil
    var onRemove: ((Track) -> Void)? = nil
    var playIsFavorites: Bool = false
    var topInset: CGFloat = 0

    @EnvironmentObject var player: PlayerController

    // Held as plain @State (NOT @StateObject) so mutating its @Published values
    // does NOT re-render this view / the List — only the indicator subview,
    // which observes it, re-renders. Same trick as ScrollObserver.
    @State private var pullObserver = PullObserver()
    @State private var scrollObserver = ScrollObserver()
    private let pullThreshold: CGFloat = 80

    var body: some View {
        if let error {
            errorState(error)
        } else if tracks.isEmpty && !isLoading {
            ContentUnavailableView(emptyTitle, systemImage: emptyImage,
                                   description: Text(emptyMessage))
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(tracks) { track in
                row(for: track)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, topInset, for: .scrollContent)
        .scrollBounceBehavior(.always)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .customScrollbar(scrollObserver)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            max(0, -geo.contentOffset.y - geo.contentInsets.top)
        } action: { _, amount in
            guard onRefresh != nil else { return }
            // Mutates the observer only — does not re-render the List.
            pullObserver.pull = amount
            if amount > pullThreshold { pullObserver.armed = true }
        }
        .onScrollPhaseChange { _, phase in
            if pullObserver.armed, !pullObserver.refreshing,
               phase != .interacting, phase != .tracking {
                startRefresh()
            }
        }
        .overlay(alignment: .top) {
            if onRefresh != nil {
                RefreshIndicator(observer: pullObserver, threshold: pullThreshold)
            }
        }
    }

    private func row(for track: Track) -> some View {
        TrackRow(track: track,
                 isCurrent: player.currentTrack?.id == track.id,
                 isPlaying: player.isPlaying)
            .contentShape(Rectangle())
            .onTapGesture {
                if player.currentTrack?.id == track.id {
                    player.togglePlayPause()
                } else {
                    player.play(track, in: tracks, favorites: playIsFavorites)
                }
            }
            .contextMenu {
                Button { player.play(track, in: tracks, favorites: playIsFavorites) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                Button { copyLink(for: track) } label: {
                    Label("Copy link", systemImage: "link")
                }
                if let url = URL(string: "https://music.youtube.com/watch?v=\(track.id)") {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                if let onRemove {
                    Divider()
                    Button(role: .destructive) { onRemove(track) } label: {
                        Label("Remove from liked", systemImage: "heart.slash")
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let onRefresh {
                Button("Try again") { Task { await onRefresh() } }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startRefresh() {
        guard !pullObserver.refreshing, let onRefresh else { return }
        pullObserver.refreshing = true
        pullObserver.armed = false
        Task {
            await onRefresh()
            withAnimation(.easeOut(duration: 0.25)) { pullObserver.refreshing = false }
        }
    }

    private func copyLink(for track: Track) {
        let url = "https://music.youtube.com/watch?v=\(track.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}

/// A circular indicator that winds up as you pull, then spins while refreshing.
private struct PullRefreshIndicator: View {
    let progress: Double
    let refreshing: Bool
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: refreshing ? 0.75 : max(0.04, progress * 0.95))
            .stroke(.secondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(refreshing ? (spin ? 360 : 0) : progress * 300))
            .opacity(refreshing ? 1 : progress)
            .padding(10)
            .glassEffect(.regular, in: Circle())
            .onChange(of: refreshing) { _, isOn in
                if isOn {
                    withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                } else {
                    spin = false
                }
            }
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    // Hover lives in the row, so hovering only re-renders THIS row — not the
    // whole list. Scrolling under a stationary pointer no longer churns state.
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: track.thumbnailURL, isCurrent: isCurrent, isPlaying: isPlaying)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(track.durationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: 52)
        .background {
            if isCurrent || hovered {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(isCurrent ? 1 : 0.7)
                    .padding(.vertical, 3)
            }
        }
        .overlay(alignment: .leading) {
            if isCurrent {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 18)
                    .offset(x: -3)
            }
        }
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.2)) { hovered = h }
        }
    }
}

/// Tracks pull-to-refresh state without re-rendering the List. Only the
/// indicator subview observes it; the list holds it as plain @State.
final class PullObserver: ObservableObject {
    @Published var pull: CGFloat = 0
    @Published var refreshing = false
    var armed = false
}

/// The pull-to-refresh indicator — the ONLY view subscribed to PullObserver,
/// so per-frame pull updates re-render just this, never the list.
private struct RefreshIndicator: View {
    @ObservedObject var observer: PullObserver
    let threshold: CGFloat

    var body: some View {
        if observer.pull > 2 || observer.refreshing {
            PullRefreshIndicator(progress: min(1, observer.pull / threshold),
                                 refreshing: observer.refreshing)
                .padding(.top, 8)
                .offset(y: observer.refreshing ? 4 : min(observer.pull * 0.35, 26))
                .allowsHitTesting(false)
        }
    }
}

private struct Thumbnail: View {
    let url: URL?
    let isCurrent: Bool
    let isPlaying: Bool

    private let size: CGFloat = 44
    private let radius: CGFloat = 8

    var body: some View {
        ZStack {
            CachedImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.quaternary)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

            if isCurrent {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.4))
                    .frame(width: size, height: size)
                EqualizerView(playing: isPlaying)
            }
        }
    }
}
