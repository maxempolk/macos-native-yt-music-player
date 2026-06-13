import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var library: LibraryModel
    @EnvironmentObject var player: PlayerController
    @State private var showingLogin = false
    @State private var keyMonitor: Any?

    var body: some View {
        Group {
            if session.isAuthenticated {
                mainView
            } else {
                signedOutView
            }
        }
        .background(VisualEffectBackground().ignoresSafeArea())
        .background(WindowConfigurator())
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
        LikedSongsView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingBar()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await library.loadLiked() }
                    } label: {
                        // Swap the icon for a spinner in place, so the indicator
                        // never overflows next to the button.
                        if library.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(library.isLoading)
                    .help("Refresh liked songs")
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .onAppear(perform: installSpacebarToggle)
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
