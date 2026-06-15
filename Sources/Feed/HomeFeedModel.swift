import Foundation

/// Builds the Home feed as explicit shelves, loaded progressively:
/// "Послушать ещё раз" (local history) → "Рекомендуем" (personalized home) →
/// "Новые релизы" (catalog). Each appears as soon as it's ready.
@MainActor
final class HomeFeedModel: ObservableObject {
    @Published private(set) var shelves: [Shelf] = []
    @Published private(set) var isLoading = false

    private let client: InnerTubeClient
    private let history: PlayHistoryStore
    private var loadedOnce = false

    init(client: InnerTubeClient, history: PlayHistoryStore) {
        self.client = client
        self.history = history
    }

    func load(force: Bool = false) async {
        if loadedOnce && !force {
            rebuild(recommended: cachedRecommended, new: cachedNew)
            return
        }

        rebuild(recommended: [], new: [])   // 1. local "Listen again" instantly

        isLoading = true
        if let rec = try? await client.newReleases() {
            cachedRecommended = rec
            rebuild(recommended: rec, new: cachedNew)
        }
        if let new = try? await client.catalogNewReleases() {
            cachedNew = new
            rebuild(recommended: cachedRecommended, new: new)
        }
        loadedOnce = true
        isLoading = false
    }

    // MARK: - Compose

    private var cachedRecommended: [Track] = []
    private var cachedNew: [Track] = []

    private func rebuild(recommended: [Track], new: [Track]) {
        var result: [Shelf] = []
        let recent = history.recentTracks
        if !recent.isEmpty {
            result.append(Shelf(id: "local-listen-again", title: "Послушать ещё раз", items: recent))
        }
        if !recommended.isEmpty {
            result.append(Shelf(id: "home-recommended", title: "Рекомендуем", items: recommended))
        }
        if !new.isEmpty {
            result.append(Shelf(id: "home-new", title: "Новые релизы", items: new))
        }
        shelves = result
    }
}
