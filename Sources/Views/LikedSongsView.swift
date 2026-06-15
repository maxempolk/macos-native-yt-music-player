import SwiftUI
import AppKit

struct LikedSongsView: View {
    @EnvironmentObject var library: LibraryModel
    @EnvironmentObject var player: PlayerController

    // Custom pull-to-refresh state.
    @State private var pull: CGFloat = 0
    @State private var pullArmed = false
    @State private var refreshing = false
    @State private var scrollObserver = ScrollObserver()
    @State private var hoveredID: String?
    private let pullThreshold: CGFloat = 80

    private func startRefresh() {
        guard !refreshing else { return }
        refreshing = true
        pullArmed = false
        Task {
            await library.loadLiked()
            withAnimation(.easeOut(duration: 0.25)) { refreshing = false }
        }
    }

    private func copyLink(for track: Track) {
        let url = "https://music.youtube.com/watch?v=\(track.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let error = library.error {
            errorState(error)
        } else if library.likedTracks.isEmpty && !library.isLoading {
            ContentUnavailableView("No liked songs yet",
                                   systemImage: "heart",
                                   description: Text("Like songs in YouTube Music and they'll show up here."))
        } else {
            List {
                ForEach(library.likedTracks) { track in
                    row(for: track)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollBounceBehavior(.always)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .customScrollbar(scrollObserver)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, -geo.contentOffset.y - geo.contentInsets.top)
            } action: { _, amount in
                pull = amount
                if amount > pullThreshold { pullArmed = true }
            }
            .onScrollPhaseChange { _, phase in
                if pullArmed, !refreshing, phase != .interacting, phase != .tracking {
                    startRefresh()
                }
            }
            .overlay(alignment: .top) { refreshIndicator }
        }
    }

    // MARK: - Row

    private func row(for track: Track) -> some View {
        TrackRow(track: track,
                 isCurrent: player.currentTrack?.id == track.id,
                 isPlaying: player.isPlaying)
            .contentShape(Rectangle())
            .onTapGesture {
                if player.currentTrack?.id == track.id {
                    player.togglePlayPause()
                } else {
                    player.play(track, in: library.likedTracks)
                }
            }
            .contextMenu {
                Button { player.play(track, in: library.likedTracks) } label: {
                    Label("Play", systemImage: "play.fill")
                }
                Button { copyLink(for: track) } label: {
                    Label("Copy link", systemImage: "link")
                }
                if let url = URL(string: "https://music.youtube.com/watch?v=\(track.id)") {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Divider()
                Button(role: .destructive) {
                    Task { await library.unlike(track) }
                } label: {
                    Label("Remove from liked", systemImage: "heart.slash")
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(rowBackground(for: track))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.28)) {
                    if hovering { hoveredID = track.id }
                    else if hoveredID == track.id { hoveredID = nil }
                }
            }
    }

    @ViewBuilder
    private var refreshIndicator: some View {
        if pull > 2 || refreshing {
            PullRefreshIndicator(progress: min(1, pull / pullThreshold), refreshing: refreshing)
                .padding(.top, 8)
                .offset(y: refreshing ? 4 : min(pull * 0.35, 26))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func rowBackground(for track: Track) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        let isHovered = hoveredID == track.id
        if isCurrent || isHovered {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.vertical, 3)
                .opacity(isCurrent ? 1 : 0.7)
        } else {
            Color.clear
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await library.loadLiked() } }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .overlay(alignment: .leading) {
            // One restrained accent: a thin bar marking the active track.
            if isCurrent {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 18)
                    .offset(x: -3)
            }
        }
    }
}

private struct Thumbnail: View {
    let url: URL?
    let isCurrent: Bool
    let isPlaying: Bool

    // Artwork radius is concentric with the row's pill (12) minus the inset.
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
