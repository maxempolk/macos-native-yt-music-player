import SwiftUI
import AppKit
import CryptoKit

/// Loads remote images through a two-tier cache (in-memory NSCache + disk), so
/// thumbnails aren't re-downloaded while scrolling or after a refresh. Keeps the
/// long liked-songs list scrolling smoothly.
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSURL, NSImage>()
    private let dir: URL
    private let session: URLSession

    private init() {
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.maksym.tune/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 500
        session = URLSession(configuration: .default)
    }

    func image(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) { return cached }

        let file = dir.appendingPathComponent(filename(for: url))
        if let data = try? Data(contentsOf: file), let img = NSImage(data: data) {
            memory.setObject(img, forKey: key)
            return img
        }

        guard let (data, _) = try? await session.data(from: url),
              let img = NSImage(data: data) else { return nil }
        memory.setObject(img, forKey: key)
        try? data.write(to: file, options: .atomic)
        return img
    }

    /// Stable filename derived from the URL (hashValue is not stable across launches).
    private func filename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Drop-in replacement for `AsyncImage`'s content/placeholder form, backed by
/// `ImageLoader`.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                content(Image(nsImage: nsImage))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            nsImage = nil
            guard let url else { return }
            nsImage = await ImageLoader.shared.image(for: url)
        }
    }
}
