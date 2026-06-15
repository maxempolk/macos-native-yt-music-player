import SwiftUI

@main
struct TuneApp: App {
    @StateObject private var session: SessionStore
    @StateObject private var player: PlayerController
    @StateObject private var library: LibraryModel
    @StateObject private var lyrics = LyricsModel()
    @StateObject private var history: PlayHistoryStore
    @StateObject private var home: HomeFeedModel

    init() {
        let session = SessionStore()
        let client = InnerTubeClient(session: session)
        let engine = WebViewAudioEngine()
        let history = PlayHistoryStore()
        _session = StateObject(wrappedValue: session)
        _player = StateObject(wrappedValue: PlayerController(engine: engine, history: history))
        _library = StateObject(wrappedValue: LibraryModel(client: client))
        _history = StateObject(wrappedValue: history)
        _home = StateObject(wrappedValue: HomeFeedModel(client: client, history: history))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(lyrics)
                .environmentObject(history)
                .environmentObject(home)
                .frame(minWidth: 240, minHeight: 320)
        }
        .defaultSize(width: 360, height: 680)   // compact, vertical by default
        // Only the *minimum* tracks content; the actual width is driven by our
        // setFrame (lyrics open/close) and the user. Without this the window
        // defaults to auto-fitting content and randomly snaps to the min width
        // during the lyrics transition's transient layout states.
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)            // no app-name title up top
        .windowToolbarStyle(.unified)
    }
}
