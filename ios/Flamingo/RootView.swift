import FlamingoCore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum MusicTab: String, CaseIterable {
    case home = "Home", library = "Library", search = "Search"
    var symbol: String { switch self { case .home: return "house.fill"; case .library: return "square.stack.fill"; case .search: return "magnifyingglass" } }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = MusicTab.home
    @State private var presentation = PlayerPresentation()
    @State private var miniFrame: CGRect = .zero
    @State private var miniArtworkFrame: CGRect = .zero
    @State private var playerArtworkFrame: CGRect = .zero
    @State private var pendingNavigation: LibraryDestination?
    @AppStorage("playerCorner") private var playerCorner = 30.0
    @State private var settings = false
    @State private var libraryPath: [LibraryDestination] = []

    private func expandPlayer() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        presentation.settle(expanded: true, reduceMotion: reduceMotion)
    }
    private func closePlayer() { presentation.settle(expanded: false, reduceMotion: reduceMotion) }

    private var floatingDock: some View {
        VStack(spacing: 8) {
            if player.current != nil {
                MiniPlayer(presentationProgress: presentation.progress, open: expandPlayer)
                    .background { GeometryReader { proxy in
                        Color.clear.preference(key: MiniPlayerFrameKey.self, value: proxy.frame(in: .named("player-root")))
                    } }
            }
            MusicTabBar(selection: $tab)
        }.padding(.horizontal, 20).padding(.bottom, 8)
    }

    var body: some View {
        @Bindable var library = library
        @Bindable var player = player
        GeometryReader { geometry in
        let fullFrame = CGRect(x: 0, y: -geometry.safeAreaInsets.top, width: geometry.size.width,
                               height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
        let source = miniFrame.isEmpty ? CGRect(x: 20, y: geometry.size.height - 128, width: max(1, geometry.size.width - 40), height: 50) : miniFrame
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
                .overlay { Color.black.opacity(0.12 * presentation.progress).allowsHitTesting(false) }
                .accessibilityHidden(presentation.isPresented).allowsHitTesting(!presentation.isPresented)
            ZStack(alignment: .bottom) {
                DockArtworkGlow(track: player.current)
                    .frame(height: 200 + geometry.safeAreaInsets.bottom)
                    .offset(y: geometry.safeAreaInsets.bottom)
                    .allowsHitTesting(false).accessibilityHidden(true)
                floatingDock
            }.opacity(1 - presentation.progress)
                .accessibilityHidden(presentation.isPresented).allowsHitTesting(!presentation.isPresented).zIndex(1)
            if player.current != nil {
                NowPlayingView(presentation: presentation, safeArea: geometry.safeAreaInsets,
                               transitionTravel: max(1, source.minY - fullFrame.minY), close: closePlayer)
                    .environment(presentation)
                    .frame(width: fullFrame.width, height: fullFrame.height)
                    .modifier(PlayerContainerTransform(progress: presentation.progress, motion: presentation,
                                                       collapsed: source, expanded: fullFrame,
                                                       corner: CGFloat(max(25, playerCorner)), reduceMotion: reduceMotion))
                    .allowsHitTesting(presentation.isPresented && pendingNavigation == nil).accessibilityHidden(!presentation.isPresented)
                    .zIndex(2)
                if !playerArtworkFrame.isEmpty, !miniArtworkFrame.isEmpty, !reduceMotion {
                    AnimatedAlbumArtwork(track: player.current, active: presentation.isPresented && player.isPlaying)
                        .modifier(PlayerArtworkTransform(progress: presentation.progress, collapsed: miniArtworkFrame,
                                                         expanded: playerArtworkFrame.offsetBy(dx: fullFrame.minX, dy: fullFrame.minY),
                                                         paused: !player.isPlaying && playerArtworkFrame.width > 100))
                        .animation(PlayerMotion.artwork, value: player.isPlaying)
                        .animation(PlayerMotion.panel, value: playerArtworkFrame)
                        .allowsHitTesting(false).accessibilityHidden(true).zIndex(3)
                }
            }
        }
        .coordinateSpace(name: "player-root")
        .onPreferenceChange(MiniPlayerFrameKey.self) { if !$0.isEmpty { miniFrame = $0 } }
        .onPreferenceChange(MiniArtworkFrameKey.self) { if !$0.isEmpty { miniArtworkFrame = $0 } }
        .onPreferenceChange(PlayerArtworkFrameKey.self) { playerArtworkFrame = $0 }
        .onChange(of: geometry.size) { _, _ in
            if presentation.phase == .dragging { presentation.settle(expanded: true, reduceMotion: reduceMotion) }
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
            .onChange(of: player.current?.id) { _, id in if id == nil { presentation.reset() } }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active, presentation.phase == .dragging {
                    presentation.settle(expanded: true, reduceMotion: true)
                }
            }
            .onChange(of: library.navigationTarget) { _, target in
                guard let target else { return }
                library.navigationTarget = nil
                if presentation.isPresented {
                    pendingNavigation = target
                    closePlayer()
                } else { tab = .library; libraryPath = [target] }
            }
            .onChange(of: presentation.phase) { _, phase in
                if phase == .collapsed, let target = pendingNavigation {
                    pendingNavigation = nil
                    tab = .library; libraryPath = [target]
                }
            }
    }
}

private struct MusicTabBar: View {
    @Binding var selection: MusicTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedIndex: Int { MusicTab.allCases.firstIndex(of: selection) ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MusicTab.allCases, id: \.self) { destination in
                Button {
                    guard selection != destination else { return }
                    // Switch content immediately; only the dock owns the spring.
                    selection = destination
                } label: {
                    VStack(spacing: 2) {
                        Group {
                            if destination == .library {
                                LibraryTabIcon().frame(width: 25, height: 28)
                            } else {
                                Image(systemName: destination.symbol)
                                    .font(.system(size: 25, weight: destination == .search ? .regular : .semibold))
                            }
                        }.frame(height: 28).accessibilityHidden(true)
                        Text(destination.rawValue).font(MusicTypography.tabLabel)
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(selection == destination ? Color.blue : Color.primary)
                    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.16), value: selection)
                    .contentShape(Capsule())
                }
                .buttonStyle(TabPressStyle())
                .accessibilityIdentifier("tab-\(destination)")
                .accessibilityAddTraits(selection == destination ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            GeometryReader { geometry in
                let itemWidth = geometry.size.width / CGFloat(MusicTab.allCases.count)
                // Keep one persistent capsule so interrupted springs retain their
                // presentation position and velocity during rapid selection changes.
                Capsule().fill(.primary.opacity(0.075))
                    .frame(width: itemWidth, height: geometry.size.height)
                    .offset(x: CGFloat(selectedIndex) * itemWidth)
                    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: selection)
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .padding(4).background(.ultraThinMaterial)
        .overlay {
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.75).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.1), radius: 16, y: 5)
    }
}

private struct TabPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.88), value: configuration.isPressed)
    }
}

struct MiniPlayer: View {
    var presentationProgress: CGFloat
    var open: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            Button(action: open) {
                HStack(spacing: 10) {
                    ArtworkView(track: player.current, radius: 5)
                        .frame(width: 32, height: 32)
                        .modifier(MiniArtworkVisibility(progress: presentationProgress, reduceMotion: reduceMotion))
                        .background { GeometryReader { proxy in
                            Color.clear.preference(key: MiniArtworkFrameKey.self, value: proxy.frame(in: .named("player-root")))
                        } }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(player.current?.title ?? "").font(MusicTypography.compactHeadline)
                        Text(player.current?.artist ?? "").font(MusicTypography.caption)
                    }.lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : PlayerMotion.panel, value: player.current?.id)
                        .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("mini-player")
            Button(action: player.toggle) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(MusicTypography.title).frame(width: 44, height: 44)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace)) }
                .foregroundStyle(.primary).accessibilityLabel(player.isPlaying ? "暂停" : "播放").accessibilityIdentifier("mini-player-play-pause")
            Button { if player.next() { PlayerHaptics.shared.discreteSelection() } } label: {
                Image(systemName: "forward.fill").font(.system(size: 25)).frame(width: 44, height: 44)
            }.foregroundStyle(.primary).accessibilityLabel("下一曲").accessibilityIdentifier("mini-player-next").disabled(!player.canGoNext)
        }.buttonStyle(PressStyle()).padding(.leading, 18).padding(.trailing, 10).frame(height: 50)
            .overlay(alignment: .bottom) { MiniPlaybackProgress(visible: presentationProgress == 0).frame(height: 2).padding(.horizontal, 20).allowsHitTesting(false) }
            .background(.ultraThinMaterial)
                .overlay { Capsule().fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)).allowsHitTesting(false) }
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 0.75) }
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)

    }
}

private struct MiniPlaybackProgress: View {
    var visible: Bool
    @Environment(PlayerStore.self) private var player
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TimelineView(.animation(paused: !visible || !player.isPlaying || phase != .active)) { _ in
            GeometryReader { geometry in
                let fraction = player.duration > 0 ? min(1, max(0, player.lyricPlaybackTime / player.duration)) : 0
                Capsule().fill(.primary.opacity(0.25)).frame(width: geometry.size.width * fraction)
            }
        }.accessibilityHidden(true)
    }
}
