import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var lyrics: LyricsModel
    @State private var scrollObserver = ScrollObserver()

    var body: some View {
        Group {
            switch lyrics.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                message("No lyrics found", systemImage: "text.quote")
            case .instrumental:
                message("Instrumental", systemImage: "music.note")
            case .loaded:
                lyricsScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentIndex: Int? {
        lyrics.currentIndex(at: player.currentTime)
    }

    private var lyricsScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(lyrics.lines) { line in
                        let isCurrent = lyrics.synced && line.id == currentIndex
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.title3)
                            .fontWeight(isCurrent ? .bold : .regular)
                            .foregroundStyle(lineColor(isCurrent: isCurrent))
                            .scaleEffect(isCurrent ? 1.04 : 1, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if lyrics.synced { player.seek(to: line.time) }
                            }
                            .animation(.easeInOut(duration: 0.2), value: isCurrent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .customScrollbar(scrollObserver)
            .onChange(of: currentIndex) { _, idx in
                guard let idx else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    private func lineColor(isCurrent: Bool) -> Color {
        if !lyrics.synced { return .primary }
        return isCurrent ? .primary : .secondary.opacity(0.55)
    }

    private func message(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
