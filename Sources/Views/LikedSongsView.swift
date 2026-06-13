import SwiftUI
import AppKit

struct LikedSongsView: View {
    @EnvironmentObject var library: LibraryModel
    @EnvironmentObject var player: PlayerController

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
            List(library.likedTracks) { track in
                TrackRow(track: track,
                         isCurrent: player.currentTrack?.id == track.id,
                         isPlaying: player.isPlaying)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if player.currentTrack?.id == track.id {
                            player.togglePlayPause()   // tap the playing track again = pause/resume
                        } else {
                            player.play(track, in: library.likedTracks)
                        }
                    }
                    .contextMenu {
                        Button {
                            player.play(track, in: library.likedTracks)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        Button {
                            copyLink(for: track)
                        } label: {
                            Label("Copy link", systemImage: "link")
                        }
                        if let url = URL(string: "https://music.youtube.com/watch?v=\(track.id)") {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
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
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func rowBackground(for track: Track) -> some View {
        if player.currentTrack?.id == track.id {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.tint.opacity(0.12))
                .padding(.vertical, 2)
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
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(track.durationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct Thumbnail: View {
    let url: URL?
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        ZStack {
            CachedImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if isCurrent {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.4))
                    .frame(width: 40, height: 40)
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .foregroundStyle(.white)
                    .font(.caption)
            }
        }
    }
}
