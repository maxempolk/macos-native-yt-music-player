import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var library: LibraryModel
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var lyrics: LyricsModel
    @State private var showingLogin = false
    @State private var keyMonitor: Any?
    @State private var leftPinnedWidth: CGFloat? // fixed left-column width while lyrics are shown
    @State private var lyricsPaneVisible = false // pane shown only AFTER the window has grown

    var body: some View {
        Group {
            if session.isAuthenticated {
                mainView
            } else {
                signedOutView
            }
        }
        .background {
            AmbientArtwork(url: player.currentTrack?.thumbnailURL)
                .animation(.easeInOut(duration: 0.6), value: player.currentTrack?.id)
        }
        .background(VisualEffectBackground().ignoresSafeArea())
        .background(WindowConfigurator())
        .background(HideSystemScrollers())
        .overlay(alignment: .topLeading) {
            if session.isAuthenticated { trafficLightBacking }
        }
        .sheet(isPresented: $showingLogin) {
            LoginSheet()
                .environmentObject(session)
        }
        .onChange(of: session.isAuthenticated) { _, authed in
            if authed { Task { await library.loadLiked() } }
        }
        .onChange(of: library.likedTracks) { _, tracks in
            player.reconcile(with: tracks)
        }
        .task {
            if session.isAuthenticated { await library.loadLiked() }
        }
    }

    private var mainView: some View {
        HStack(spacing: 0) {
            // Left: track list + now-playing bar. Pinned to a fixed width while
            // lyrics are shown so nothing here reflows/jitters as the window grows.
            LikedSongsView()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NowPlayingBar()
                }
                .frame(maxWidth: leftPinnedWidth == nil ? .infinity : nil)
                .frame(width: leftPinnedWidth)
            if lyricsPaneVisible {
                Divider()
                // Right: lyrics, full height — emerges from underneath.
                LyricsView()
                    .frame(maxWidth: .infinity)
                    .transition(.offset(y: 36).combined(with: .opacity))
            }
        }
            // Keep the left column pinned to the leading edge instead of letting
            // the HStack center it while the window is wide but lyrics are gone.
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
                // Auto-collapse lyrics once the window gets too narrow for a split.
                if player.showLyrics, lyricsPaneVisible, width < lyricsMinTotalWidth {
                    autoHideLyrics()
                }
            }
            .onAppear {
                installSpacebarToggle()
                restoreLyricsModeIfNeeded()
            }
            .onChange(of: player.showLyrics) { _, show in
                if show {
                    if !lyricsPaneVisible { openLyrics() }   // skip when restoring
                    Task { await lyrics.load(for: player.currentTrack) }
                } else if lyricsPaneVisible {
                    closeLyrics()
                }
                UserDefaults.standard.set(show, forKey: Self.lyricsOpenKey)
            }
            .onChange(of: player.currentTrack?.id) { _, _ in
                if player.showLyrics { Task { await lyrics.load(for: player.currentTrack) } }
            }
    }

    private static let lyricsOpenKey = "tune.lyricsOpen"
    @State private var didRestore = false

    private func keyWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    /// Width below which lyrics auto-collapse back to a single pane.
    private let lyricsMinTotalWidth: CGFloat = 540

    /// Reopens in the same mode the app was last closed in. If lyrics were open,
    /// the window was restored at ~2× by macOS, so we just re-show the pane —
    /// the split is a live 50/50, no pinning needed.
    private func restoreLyricsModeIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        guard UserDefaults.standard.bool(forKey: Self.lyricsOpenKey) else { return }
        DispatchQueue.main.async {
            leftPinnedWidth = nil
            lyricsPaneVisible = true
            player.showLyrics = true   // onChange skips openLyrics (pane already visible)
            Task { await lyrics.load(for: player.currentTrack) }
        }
    }

    /// Opens lyrics jitter-free by staging it across run-loop ticks: pin the
    /// left width, grow the window (WITHOUT the pane so the left can't be
    /// squeezed), reveal the pane, then release the pin so the split becomes a
    /// live 50/50 that tracks window resizing.
    private func openLyrics() {
        guard let win = keyWindow() else { return }
        let w = win.frame.width
        leftPinnedWidth = w
        DispatchQueue.main.async {
            guard let win = keyWindow() else { return }
            var frame = win.frame
            frame.size.width = w * 2
            if let visible = win.screen?.visibleFrame, frame.maxX > visible.maxX {
                frame.origin.x = max(visible.minX, visible.maxX - frame.width)
            }
            win.setFrame(frame, display: true, animate: false)
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.28)) { lyricsPaneVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    leftPinnedWidth = nil   // release → live 50/50
                }
            }
        }
    }

    /// Manual close: pin the left at its current half, animate the pane out,
    /// then shrink the window to that half (single pane restored).
    private func closeLyrics() {
        guard let win = keyWindow() else { return }
        let target = win.frame.width / 2
        leftPinnedWidth = target
        withAnimation(.easeIn(duration: 0.22)) { lyricsPaneVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let win = keyWindow() {
                var frame = win.frame
                frame.size.width = target
                win.setFrame(frame, display: true, animate: false)
            }
            leftPinnedWidth = nil
        }
    }

    /// Auto-collapse when the window gets too narrow: hide the pane in place,
    /// letting the list fill the (already small) window — no resize.
    private func autoHideLyrics() {
        withAnimation(.easeIn(duration: 0.22)) { lyricsPaneVisible = false }
        leftPinnedWidth = nil
        player.showLyrics = false   // onChange skips closeLyrics (pane already hidden)
    }

    /// Space toggles play/pause regardless of which control is focused
    /// (skipped only while typing in a text field).
    private func installSpacebarToggle() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 else { return event }   // 49 = space
            let responder = NSApp.keyWindow?.firstResponder
            if responder is NSTextView { return event }       // let text fields keep space
            player.togglePlayPause()
            return nil                                         // consume the event
        }
    }

    /// A small frosted backing with a rounded bottom-right corner that sits
    /// behind the traffic lights so they don't get lost over busy backgrounds.
    /// Uses the behind-window blur (samples the static desktop) rather than a
    /// material — a material would sample the scrolling track list and flicker.
    private var trafficLightBacking: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 0,
            bottomTrailingRadius: 18, topTrailingRadius: 0, style: .continuous
        )
        return VisualEffectBackground()
            .clipShape(shape)
            .frame(width: 82, height: 30)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .ignoresSafeArea()
    }

    private var signedOutView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Tune")
                .font(.largeTitle.bold())
            Text("Sign in with your YouTube Music account to load your liked songs.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Sign in") { showingLogin = true }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
