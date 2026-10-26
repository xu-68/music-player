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
    @AppStorage("barBlur") private var barBlur = false
    @Namespace private var playerNamespace

    private func expandPlayer() { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring) { expanded = true } }
    private func closePlayer() { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : MusicDesign.spring) { expanded = false } }

    var body: some View {
        @Bindable var library = library
        @Bindable var player = player
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $tab) {
                    NavigationStack { HomeView(importAction: { Task { await library.scanMusic() } }, settingsAction: { settings = true }) }
                        .tag(MusicTab.home).toolbar(.hidden, for: .tabBar)
                    NavigationStack(path: $libraryPath) {
                        LibraryView(importAction: { Task { await library.scanMusic() } })
                            .navigationDestination(for: LibraryDestination.self) { destination in
                                switch destination {
                                case .artist(let name): ArtistDetailView(artist: name)
                                case .album(let key): AlbumDetailView(albumKey: key)
                                }
                            }
                    }
                        .tag(MusicTab.library).toolbar(.hidden, for: .tabBar)
                    NavigationStack { StatsView(settingsAction: { settings = true }) }
                        .tag(MusicTab.stats).toolbar(.hidden, for: .tabBar)
                }.toolbar(.hidden, for: .tabBar).clipped()
                VStack(spacing: 4) {
                    if player.current != nil {
                        MiniPlayer(namespace: playerNamespace, expanded: expanded, open: expandPlayer)
                            .padding(.horizontal, 8).padding(.top, 4)
                    }
                    HStack(spacing: 0) {
                        ForEach(MusicTab.allCases, id: \.self) { item in
                            Button { tab = item } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: item.symbol).font(.system(size: 23, weight: .medium))
                                        .overlay {
                                            if item == .library { Image(systemName: "music.note").font(.system(size: 12, weight: .semibold)).offset(y: 2).blendMode(.destinationOut) }
                                        }.compositingGroup().frame(height: 26)
                                    Text(item.rawValue).font(.system(size: 10, weight: .medium))
                                }.foregroundStyle(tab == item ? MusicDesign.accent : Color.secondary)
                                    .frame(maxWidth: .infinity).frame(height: 49).contentShape(Rectangle())
                            }.buttonStyle(PressStyle()).accessibilityAddTraits(tab == item ? .isSelected : [])
                                .accessibilityIdentifier("tab-\(item)")
                        }
                    }
                }.background {
                    if barBlur { Rectangle().fill(.bar) }
                    else { Color(uiColor: .systemBackground) }
                }.compositingGroup().zIndex(1)
            }.accessibilityHidden(expanded).allowsHitTesting(!expanded)
                .scaleEffect(expanded && !reduceMotion ? 0.96 : 1, anchor: .top)
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
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
