import FlamingoCore
import SwiftUI
import UniformTypeIdentifiers

enum MusicTab: String, CaseIterable {
    case home = "主页", library = "资料库", stats = "统计"
    var symbol: String { switch self { case .home: return "music.note"; case .library: return "square.stack.fill"; case .stats: return "chart.line.uptrend.xyaxis" } }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = MusicTab.home
    @State private var expanded = false
    @State private var settings = false
    @State private var libraryPath: [LibraryDestination] = []
    @Namespace private var playerNamespace

    private func expandPlayer() { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring) { expanded = true } }
    private func closePlayer() { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring) { expanded = false } }

    private var floatingDock: some View {
        VStack(spacing: 10) {
            if player.current != nil {
                MiniPlayer(namespace: playerNamespace, expanded: expanded, open: expandPlayer)
            }
            HStack(spacing: 0) {
                ForEach(MusicTab.allCases, id: \.self) { destination in
                    Button { tab = destination } label: {
                        VStack(spacing: 3) {
                            Image(systemName: destination.symbol).font(.system(size: 22, weight: .semibold))
                            Text(destination.rawValue).font(.system(size: 10, weight: .medium))
                        }.frame(maxWidth: .infinity).frame(height: 54)
                            .foregroundStyle(tab == destination ? MusicDesign.accent : Color.primary.opacity(0.65))
                            .background {
                                if tab == destination { Capsule().fill(.primary.opacity(0.06)).padding(4) }
                            }.contentShape(Capsule())
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("tab-\(destination)")
                        .accessibilityAddTraits(tab == destination ? .isSelected : [])
                }
            }.padding(4).background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.1), radius: 16, y: 5)
                .padding(.horizontal, 12)
        }.padding(.horizontal, 8).padding(.bottom, 8)
    }

    var body: some View {
        @Bindable var library = library
        @Bindable var player = player
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            TabView(selection: $tab) {
                NavigationStack { HomeView(importAction: { Task { await library.scanMusic() } }, settingsAction: { settings = true }) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: player.current == nil ? 78 : 146).allowsHitTesting(false) }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(MusicTab.home.rawValue, systemImage: MusicTab.home.symbol).accessibilityIdentifier("tab-home") }
                    .tag(MusicTab.home)
                NavigationStack(path: $libraryPath) {
                    LibraryView(importAction: { Task { await library.scanMusic() } })
                        .navigationDestination(for: LibraryDestination.self) { destination in
                            switch destination {
                            case .artist(let name): ArtistDetailView(artist: name)
                            case .album(let key): AlbumDetailView(albumKey: key)
                            }
                        }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: player.current == nil ? 78 : 146).allowsHitTesting(false) }
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label(MusicTab.library.rawValue, systemImage: MusicTab.library.symbol).accessibilityIdentifier("tab-library") }
                .tag(MusicTab.library)
                NavigationStack { StatsView(settingsAction: { settings = true }) }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: player.current == nil ? 78 : 146).allowsHitTesting(false) }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(MusicTab.stats.rawValue, systemImage: MusicTab.stats.symbol).accessibilityIdentifier("tab-stats") }
                    .tag(MusicTab.stats)
            }.tint(MusicDesign.accent)
                .accessibilityHidden(expanded).allowsHitTesting(!expanded)
                .scaleEffect(expanded && !reduceMotion ? 0.96 : 1, anchor: .top)
            ZStack(alignment: .bottom) {
                DockArtworkGlow(track: player.current).frame(height: 200)
                    .allowsHitTesting(false).accessibilityHidden(true)
                floatingDock
            }.accessibilityHidden(expanded).allowsHitTesting(!expanded).zIndex(1)
            ZStack {
                if expanded, player.current != nil {
                    NowPlayingView(namespace: playerNamespace, safeArea: geometry.safeAreaInsets, close: closePlayer)
                        .ignoresSafeArea()
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).zIndex(2)
                .allowsHitTesting(expanded).accessibilityHidden(!expanded)
        }
        }.sheet(isPresented: $settings) { SettingsView() }
            .sheet(item: $library.playlistAddition) { request in PlaylistAdditionView(request: request) }
            .overlay(alignment: .top) {
                if library.importing {
                    HStack { ProgressView(); Text(library.importProgress).font(.footnote).lineLimit(1) }
                        .padding(12).background(.regularMaterial, in: Capsule()).padding().accessibilityLabel("正在扫描 \(library.importProgress)")
                }
            }
            .alert("资料库", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button("好") { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
            .alert("扫描完成", isPresented: Binding(get: { library.importMessage != nil }, set: { if !$0 { library.importMessage = nil } })) {
                Button("好") { library.importMessage = nil }
            } message: { Text(library.importMessage ?? "") }
            .alert("播放失败", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
                Button("好") { player.errorMessage = nil }
            } message: { Text(player.errorMessage ?? "") }
            .onChange(of: library.snapshot.tracks.map(\.id)) { _, _ in player.reconcileLibrary() }
            .onChange(of: player.current?.id) { _, id in if id == nil { closePlayer() } }
            .onChange(of: library.navigationTarget) { _, target in
                guard let target else { return }
                library.navigationTarget = nil
                if expanded {
                    // Finish the shared-artwork transition before UIKit starts
                    // a tab/navigation transition, so neither snapshots the dock
                    // while it is scaled or hidden behind the player.
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring,
                                  completionCriteria: .logicallyComplete) {
                        expanded = false
                    } completion: {
                        tab = .library; libraryPath = [target]
                    }
                } else { tab = .library; libraryPath = [target] }
            }
    }
}

struct MiniPlayer: View {
    var namespace: Namespace.ID
    var expanded: Bool
    var open: () -> Void
    @Environment(PlayerStore.self) private var player
    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    ArtworkView(track: player.current, radius: 6)
                        .matchedGeometryEffect(id: "player-artwork", in: namespace, isSource: !expanded)
                        .frame(width: 42, height: 42).opacity(expanded ? 0 : 1)
                    Text(player.current?.title ?? "").font(.system(size: 16, weight: .medium)).lineLimit(1)
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mini-player")
            Button(action: player.toggle) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)).frame(width: 44, height: 48) }
                .foregroundStyle(.primary).accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            AirPlayButton().frame(width: 42, height: 44)
        }.padding(.leading, 8).padding(.trailing, 4).frame(height: 58)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.45), lineWidth: 0.5) }
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
            .padding(.bottom, 4)
    }
}
