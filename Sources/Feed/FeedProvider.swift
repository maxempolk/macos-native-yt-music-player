import Foundation

/// A source of tracks for one Home shelf. Implementations can be local (history)
/// or network-backed (InnerTube) — the UI only sees `[Track]`, so a provider can
/// be swapped without touching views.
@MainActor
protocol FeedProvider {
    var title: String { get }
    func items() async -> [Track]
}

/// "Listen again" — the user's locally-recorded play history.
@MainActor
struct ListenAgainProvider: FeedProvider {
    let title = "Послушать ещё раз"
    let history: PlayHistoryStore

    func items() async -> [Track] {
        history.recentTracks
    }
}
