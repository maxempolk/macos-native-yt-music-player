import SwiftUI

@main
struct TuneApp: App {
    @StateObject private var session: SessionStore
    @StateObject private var player: PlayerController
    @StateObject private var library: LibraryModel
    @StateObject private var lyrics = LyricsModel()

    init() {
        let session = SessionStore()
        let client = InnerTubeClient(session: session)
        let engine = WebViewAudioEngine()
        _session = StateObject(wrappedValue: session)
        _player = StateObject(wrappedValue: PlayerController(engine: engine))
        _library = StateObject(wrappedValue: LibraryModel(client: client))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(player)
                .environmentObject(library)
                .environmentObject(lyrics)
                .frame(minWidth: 240, minHeight: 320)
        }
        .defaultSize(width: 360, height: 680)   // compact, vertical by default
        .windowStyle(.hiddenTitleBar)            // no app-name title up top
        .windowToolbarStyle(.unified)
    }
}
