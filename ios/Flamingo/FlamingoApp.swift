import SwiftUI

enum AppPreferences {
    static let defaults = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        ? UserDefaults(suiteName: "org.flamingo.local.uitests")! : UserDefaults.standard
}

@main @MainActor struct FlamingoApp: App {
    @State private var library: LibraryStore
    @State private var player: PlayerStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PlayerPreferences.register()
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
                .font(MusicTypography.body)
                .defaultAppStorage(AppPreferences.defaults)
                .task { if AppPreferences.defaults.bool(forKey: "autoScanMusic") { await library.scanMusic(quiet: true) } }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { PlayerHaptics.shared.releaseResources() }
                    player.synchronizeSystemPlayback()
                    if phase == .active && AppPreferences.defaults.bool(forKey: "autoScanMusic") {
                        Task { await library.scanMusic(quiet: true) }
                    }
                    if phase != .active { player.persistQueue(); Task { await library.saveNow() } }
                }
        }
    }
}
