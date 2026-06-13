import Foundation

/// Persists the parsed liked-songs list to the caches directory so the app can
/// show it instantly on launch while the network refresh happens in the
/// background (stale-while-revalidate).
enum LikedCache {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.maksym.tune", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("liked.json")
    }

    static func load() -> [Track]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([Track].self, from: data)
    }

    static func save(_ tracks: [Track]) {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
