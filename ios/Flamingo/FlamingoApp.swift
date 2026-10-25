import SwiftUI

enum AppPreferences {
    static let defaults = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        ? UserDefaults(suiteName: "org.flamingo.local.uitests")! : UserDefaults.standard
}

@main @MainActor struct FlamingoApp: App {
    @State private var library: LibraryStore
    @State private var player: PlayerStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { DemoLibrary.prepare() }
        #endif
        let store = LibraryStore()
        _library = State(initialValue: store)
        _player = State(initialValue: PlayerStore(library: store))
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(library).environment(player).tint(MusicDesign.accent)
                .defaultAppStorage(AppPreferences.defaults)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { player.flushListening(); Task { await library.saveNow() } }
                }
        }
    }
}
