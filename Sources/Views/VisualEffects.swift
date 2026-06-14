import SwiftUI
import AppKit

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
