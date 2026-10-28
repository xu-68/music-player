import FlamingoCore
import SwiftUI
import UniformTypeIdentifiers

enum MusicTab: String, CaseIterable {
    case home = "Home", library = "Library", search = "Search"
    var symbol: String { switch self { case .home: return "house.fill"; case .library: return "music.note.square.stack.fill"; case .search: return "magnifyingglass" } }
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
    @Namespace private var tabNamespace

    private func expandPlayer() { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring) { expanded = true } }
    private func closePlayer() { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring) { expanded = false } }

    private var floatingDock: some View {
        VStack(spacing: 8) {
            if player.current != nil {
                MiniPlayer(namespace: playerNamespace, expanded: expanded, open: expandPlayer)
            }
            HStack(spacing: 0) {
                ForEach(MusicTab.allCases, id: \.self) { destination in
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.48, dampingFraction: 0.82)) { tab = destination }
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: destination.symbol)
                                .font(.system(size: 25, weight: destination == .search ? .regular : .semibold))
                                .frame(height: 28)
                            Text(destination.rawValue).font(.system(size: 11, weight: .medium))
                        }.frame(maxWidth: .infinity).frame(height: 54)
                            .foregroundStyle(tab == destination ? Color.blue : Color.primary)
                            .background {
                                if tab == destination { Capsule().fill(.primary.opacity(0.075))
                                    .matchedGeometryEffect(id: "tab-selection", in: tabNamespace) }
                            }.contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(destination)")
                        .accessibilityAddTraits(tab == destination ? .isSelected : [])
                }
            }.padding(4).background(.ultraThinMaterial)
                .overlay { Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)).allowsHitTesting(false) }
                .clipShape(Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.75) }
                .shadow(color: .black.opacity(0.1), radius: 16, y: 5)
        }.padding(.horizontal, 20).padding(.bottom, 8)
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
                NavigationStack { SongsView(title: "Search") }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: player.current == nil ? 78 : 146).allowsHitTesting(false) }
                    .toolbar(.hidden, for: .tabBar)
                    .tabItem { Label(MusicTab.search.rawValue, systemImage: MusicTab.search.symbol).accessibilityIdentifier("tab-search") }
                    .tag(MusicTab.search)
            }.tint(MusicDesign.accent)
                .accessibilityHidden(expanded).allowsHitTesting(!expanded)
            ZStack(alignment: .bottom) {
                DockArtworkGlow(track: player.current).frame(height: 200)
                    .allowsHitTesting(false).accessibilityHidden(true)
                floatingDock
            }.accessibilityHidden(expanded).allowsHitTesting(!expanded).zIndex(1)
            ZStack {
                if expanded, player.current != nil {
                    NowPlayingView(namespace: playerNamespace, safeArea: geometry.safeAreaInsets, close: closePlayer)
                        .ignoresSafeArea()
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom))
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
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 10) {
                    ArtworkView(track: player.current, radius: 5)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(player.current?.title ?? "").font(.system(size: 14, weight: .semibold))
                        Text(player.current?.artist ?? "").font(.system(size: 13))
                    }.lineLimit(1)
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mini-player")
            Button(action: player.toggle) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)).frame(width: 44, height: 44) }
                .foregroundStyle(.primary).accessibilityLabel(player.isPlaying ? "暂停" : "播放")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 25)).frame(width: 44, height: 44)
            }.foregroundStyle(.primary).accessibilityLabel("下一曲").accessibilityIdentifier("mini-player-next").disabled(!player.canGoNext)
        }.buttonStyle(.plain).padding(.leading, 18).padding(.trailing, 10).frame(height: 50)
            .background(.ultraThinMaterial)
                .overlay { Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)).allowsHitTesting(false) }
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 0.75) }
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)

    }
}
