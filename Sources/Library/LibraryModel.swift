import Foundation

/// Loads and holds the user's liked songs.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    // "New releases" (discovery) section.
    @Published private(set) var newReleases: [Track] = []
    @Published private(set) var newReleasesLoaded = false

    private let client: InnerTubeClient

    /// videoIds the user unliked this session. YouTube's liked-songs endpoint
    /// lags behind a remove-like by minutes, so a refresh would otherwise
    /// "resurrect" a just-removed track. We filter these out of every result
    /// until the server itself stops returning them. Persisted so the tombstone
    /// survives an app restart during that lag window.
    private var removedIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(removedIds), forKey: Self.removedKey) }
    }
    private static let removedKey = "tune.removedLikes"

    init(client: InnerTubeClient) {
        self.client = client
        let stored = UserDefaults.standard.stringArray(forKey: Self.removedKey) ?? []
        self.removedIds = Set(stored)
    }

    func loadLiked() async {
        // 1. Show cached list instantly (if any) so the window isn't empty.
        if likedTracks.isEmpty, let cached = LikedCache.load() {
            likedTracks = cached.filter { !removedIds.contains($0.id) }
        }

        // 2. Refresh from the network, filling in pages live.
        isLoading = true
        error = nil
        do {
            let fresh = try await client.likedSongs { [weak self] page in
                guard let self else { return }
                self.likedTracks = page.filter { !self.removedIds.contains($0.id) }
            }
            // Drop tombstones the server has finally caught up on (no longer
            // returns), and hide any it still wrongly returns.
            let freshIds = Set(fresh.map(\.id))
            removedIds.formIntersection(freshIds)
            let visible = fresh.filter { !removedIds.contains($0.id) }
            likedTracks = visible
            LikedCache.save(visible)
        } catch {
            // Keep showing the cached list if we have one; only surface the
            // error when there's nothing to display.
            if likedTracks.isEmpty { self.error = error.localizedDescription }
        }
        isLoading = false
    }

    /// Loads "New releases" (lazily; once per launch unless refreshed).
    func loadNewReleases(force: Bool = false) async {
        if newReleasesLoaded && !force { return }
        do {
            newReleases = try await client.newReleases()
            newReleasesLoaded = true
        } catch {
            // Non-fatal: the section just shows its empty state.
            newReleasesLoaded = true
        }
    }

    /// Removes a track from "Liked Music". Optimistic: drops it from the list
    /// immediately and restores it if the server rejects the change.
    func unlike(_ track: Track) async {
        guard let index = likedTracks.firstIndex(of: track) else { return }
        likedTracks.remove(at: index)
        removedIds.insert(track.id)
        LikedCache.save(likedTracks)
        do {
            try await client.removeLike(videoId: track.id)
        } catch {
            removedIds.remove(track.id)
            likedTracks.insert(track, at: min(index, likedTracks.count))
            LikedCache.save(likedTracks)
            self.error = error.localizedDescription
        }
    }
}
