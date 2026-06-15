import SwiftUI
import AppKit

/// Main destinations: the Home feed, or the liked-tracks list (toggled by the
/// heart button). "Новые"/"Рекомендуем" now live as shelves on Home.
enum Destination {
    case home, favorites
}

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var library: LibraryModel
    @EnvironmentObject var player: PlayerController
    @EnvironmentObject var lyrics: LyricsModel
    @EnvironmentObject var history: PlayHistoryStore
    @EnvironmentObject var home: HomeFeedModel
    @State private var destination: Destination = .home
    @State private var showingLogin = false
    @State private var keyMonitor: Any?
    @State private var lyricsPaneVisible = false
    /// Content width WITHOUT the lyrics pane (the left column's width). The
    /// window is `baseWidth` when closed and `baseWidth + lyricsPaneWidth` when
    /// open. Updated only by genuine user resizes — never from our own setFrame.
    @State private var baseWidth: CGFloat = 360

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
        // Main substrate is Liquid Glass over the (clear) window, so the desktop
        // behind shows through it rather than a flat frosted fill.
        .background {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
                .ignoresSafeArea()
        }
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
        // Left column: fixed to baseWidth while lyrics are open, otherwise fills
        // the window. The pane is an OVERLAY at x=baseWidth — outside the layout
        // flow, so it never inflates the content's minimum size and the AppKit
        // window animation never fights SwiftUI. As the window grows past
        // baseWidth, the pane is revealed from the right; shrinking clips it away.
        leftColumn
            .frame(width: lyricsPaneVisible ? baseWidth : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if lyricsPaneVisible {
                    HStack(spacing: 0) {
                        Divider()
                        LyricsView().frame(width: lyricsPaneWidth)
                    }
                    .offset(x: baseWidth)
                }
            }
            // Capture ONLY genuine user resizes (drag end). No feedback loop with
            // our own setFrame, so baseWidth never catches a transient value.
            .background(UserResizeObserver { width in
                baseWidth = lyricsPaneVisible ? max(240, width - lyricsPaneWidth) : width
            })
            // Geometry is used purely to auto-collapse when too narrow.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _, width in
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

    // MARK: - Left column (Home / Favorites)

    private let contentTopInset: CGFloat = 8

    private var leftColumn: some View {
        Group {
            if destination == .home {
                HomeView(topInset: contentTopInset)
            } else {
                favoritesList
            }
        }
        .animation(.easeInOut(duration: 0.25), value: destination)
        .safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingBar() }
        .overlay(alignment: .topTrailing) { favoritesButton }
    }

    private var favoritesList: some View {
        TrackListView(
            tracks: library.likedTracks,
            isLoading: library.isLoading,
            error: library.error,
            emptyTitle: "No liked songs yet",
            emptyImage: "heart",
            emptyMessage: "Like songs in YouTube Music and they'll show up here.",
            onRefresh: { await library.loadLiked() },
            onRemove: { track in Task { await library.unlike(track) } },
            playIsFavorites: true,
            topInset: contentTopInset
        )
    }

    /// Toggles between Home and the liked-tracks list.
    private var favoritesButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                destination = (destination == .favorites) ? .home : .favorites
            }
        } label: {
            Image(systemName: destination == .favorites ? "heart.fill" : "heart")
                .font(.body.weight(.semibold))
                .foregroundStyle(destination == .favorites ? Color.accentColor : .secondary)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .padding(.top, 4)
        .padding(.trailing, 12)
        .help("Любимые")
    }

    private static let lyricsOpenKey = "tune.lyricsOpen"
    @State private var didRestore = false

    private func keyWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    private let lyricsPaneWidth: CGFloat = 380
    private let lyricsMinTotalWidth: CGFloat = 660

    /// On restore macOS already widened the window, so just show the pane.
    private func restoreLyricsModeIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        guard UserDefaults.standard.bool(forKey: Self.lyricsOpenKey) else { return }
        DispatchQueue.main.async {
            if let win = self.keyWindow() {
                self.baseWidth = max(240, win.frame.width - self.lyricsPaneWidth)
            }
            self.lyricsPaneVisible = true
            self.player.showLyrics = true
            Task { await self.lyrics.load(for: self.player.currentTrack) }
        }
    }

    /// Show the pane (instantly — it's clipped beyond the window's right edge
    /// for now) and animate the window wider; the pane is revealed as it grows.
    private func openLyrics() {
        guard let win = keyWindow(), !player.lyricsTransitioning else { return }
        player.lyricsTransitioning = true
        let base = win.frame.width
        baseWidth = base
        lyricsPaneVisible = true

        var frame = win.frame
        frame.size.width = base + lyricsPaneWidth
        if let visible = win.screen?.visibleFrame, frame.maxX > visible.maxX {
            frame.origin.x = max(visible.minX, visible.maxX - frame.width)
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().setFrame(frame, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { player.lyricsTransitioning = false }
        })
    }

    /// Animate the window back to baseWidth (clipping the pane away), then drop
    /// the pane once it's fully off-window.
    private func closeLyrics() {
        guard let win = keyWindow(), !player.lyricsTransitioning else {
            lyricsPaneVisible = false
            return
        }
        player.lyricsTransitioning = true
        var frame = win.frame
        frame.size.width = baseWidth
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().setFrame(frame, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                lyricsPaneVisible = false
                player.lyricsTransitioning = false
            }
        })
    }

    /// Auto-collapse when too narrow — drop the pane in place, no window resize.
    private func autoHideLyrics() {
        guard !player.lyricsTransitioning else { return }
        if let win = keyWindow() { baseWidth = win.frame.width }
        lyricsPaneVisible = false
        player.showLyrics = false
    }

    /// Space toggles play/pause regardless of which control is focused
    /// (skipped only while typing in a text field).
    private func installSpacebarToggle() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let responder = NSApp.keyWindow?.firstResponder
            let inTextField = responder is NSTextView
            switch event.keyCode {
            case 49:                                           // Space — toggle play/pause
                if inTextField { return event }
                player.togglePlayPause()
                return nil
            case 123:                                          // ← seek -3s
                if inTextField { return event }
                player.seek(to: max(0, player.currentTime - 3))
                return nil
            case 124:                                          // → seek +3s
                if inTextField { return event }
                player.seek(to: player.currentTime + 3)
                return nil
            case 17:                                           // T — toggle lyrics
                if inTextField { return event }
                if player.lyricsTransitioning { return nil }   // ignore mid-animation
                player.showLyrics.toggle()
                return nil
            default:
                return event
            }
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
