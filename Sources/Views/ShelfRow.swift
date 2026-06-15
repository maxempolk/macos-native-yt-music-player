import SwiftUI

/// One Home shelf: a header plus a horizontal carousel of track cards.
struct ShelfRow: View {
    let shelf: Shelf
    @EnvironmentObject var player: PlayerController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(shelf.items) { track in
                        TrackCard(
                            track: track,
                            isCurrent: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying,
                            onTap: { play(track) }
                        )
                    }
                }
                .padding(14)
            }
            // One shared glass surface behind the whole carousel, so the cards
            // read as a single grouped element rather than loose tiles.
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(shelf.title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let actionTitle = shelf.actionTitle {
                Button {
                    // TODO: open the full shelf list (future destination).
                } label: {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func play(_ track: Track) {
        if player.currentTrack?.id == track.id {
            player.togglePlayPause()
        } else {
            player.play(track, in: shelf.items)
        }
    }
}
