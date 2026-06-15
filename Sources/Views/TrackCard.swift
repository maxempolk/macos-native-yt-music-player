import SwiftUI

/// A single carousel card: artwork + title + artist on a glass tile.
struct TrackCard: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    private let width: CGFloat = 124
    private let artRadius: CGFloat = 10   // concentric inside the shelf panel

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                artwork
                Text(track.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var artwork: some View {
        ZStack {
            CachedImage(url: track.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: artRadius, style: .continuous).fill(.quaternary)
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: artRadius, style: .continuous))

            if isCurrent {
                RoundedRectangle(cornerRadius: artRadius, style: .continuous)
                    .fill(.black.opacity(0.4))
                    .frame(width: width, height: width)
                EqualizerView(playing: isPlaying)
            }
        }
    }
}
