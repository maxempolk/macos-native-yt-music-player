import SwiftUI
import AppKit

/// A faint, heavily-blurred wash of the current artwork — ambient color for the
/// window without a heavy tint. Crossfades when the track changes.
struct AmbientArtwork: View {
    let url: URL?

    var body: some View {
        CachedImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.clear
        }
        .blur(radius: 90)
        .opacity(0.10)
        .ignoresSafeArea()
        .id(url)
        .transition(.opacity)
    }
}

/// A behind-window blur, so the desktop/other apps show through faintly.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow   // sample what's behind the window
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Hides the system scrollers on every NSScrollView in the window. SwiftUI's
/// `.scrollIndicators(.hidden)` doesn't remove the *legacy* always-visible
/// scroller (shown when the user's system setting is "Always show scroll bars"),
/// so we turn it off directly and rely on our custom scrollbar instead.
struct HideSystemScrollers: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.start(anchoredTo: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private weak var anchor: NSView?
        private var timer: Timer?

        func start(anchoredTo view: NSView) {
            anchor = view
            // List/ScrollView re-enable their scroller on updates, so keep
            // enforcing it off. Cheap: only touches scrollers that are on.
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                self?.enforce()
            }
            timer?.tolerance = 0.2
        }

        private func enforce() {
            guard let root = anchor?.window?.contentView else { return }
            for scroll in Self.scrollViews(in: root) {
                if scroll.hasVerticalScroller { scroll.hasVerticalScroller = false }
                if scroll.hasHorizontalScroller { scroll.hasHorizontalScroller = false }
            }
        }

        private static func scrollViews(in view: NSView) -> [NSScrollView] {
            var found = view.subviews.flatMap { scrollViews(in: $0) }
            if let scroll = view as? NSScrollView { found.append(scroll) }
            return found
        }

        deinit { timer?.invalidate() }
    }
}

/// Reports the window's width *only* when the user finishes a live resize
/// (drag). Programmatic `setFrame(animate:false)` does NOT post
/// `didEndLiveResizeNotification`, so this avoids the feedback loop that
/// `onGeometryChange` has with our own window resizing.
struct UserResizeObserver: NSViewRepresentable {
    var onUserResize: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.onResize = onUserResize
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onResize = onUserResize
        if context.coordinator.window == nil {
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var window: NSWindow?
        var onResize: ((CGFloat) -> Void)?

        func attach(to window: NSWindow?) {
            guard let window, self.window == nil else { return }
            self.window = window
            NotificationCenter.default.addObserver(
                self, selector: #selector(didEndLiveResize(_:)),
                name: NSWindow.didEndLiveResizeNotification, object: window)
        }

        @objc private func didEndLiveResize(_ note: Notification) {
            guard let window else { return }
            onResize?(window.frame.width)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

/// Makes the hosting window non-opaque with a clear background so the
/// behind-window blur can actually show the desktop through it.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            // Let the behind-window blur fill the title bar area too, instead of
            // it rendering as a black strip over the now-transparent window.
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden       // no app-name text up top
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
