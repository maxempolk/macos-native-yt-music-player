import SwiftUI

@main
struct TuneApp: App {
    @StateObject private var session: SessionStore
    @StateObject private var player: PlayerController
    @StateObject private var library: LibraryModel

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
                .frame(minWidth: 240, minHeight: 320)
        }
        .defaultSize(width: 360, height: 680)   // compact, vertical by default
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
