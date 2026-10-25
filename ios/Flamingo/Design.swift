import AVKit
import FlamingoCore
import MediaPlayer
import SwiftUI

enum MusicDesign {
    static let accent = Color(red: 0.96, green: 0.22, blue: 0.36)
    static let spring = Animation.spring(response: 0.46, dampingFraction: 0.86)
    static let lyricSpring = Animation.spring(response: 0.55, dampingFraction: 0.9)
    static let pageInset: CGFloat = 20
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ArtworkView: View {
    var track: Track?
    var radius: CGFloat = 8
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image = ArtworkCache.shared.image(track?.artworkFilename) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: max(18, proxy.size.width * 0.3), weight: .medium))
                        .foregroundStyle(MusicDesign.accent.opacity(0.7))
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct FlowingArtworkBackground: View {
    var track: Track?
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("animatedBackground") private var animated = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active || reduceMotion || !animated || scenePhase != .active)) { context in
            let phase = reduceMotion || !animated ? 0 : context.date.timeIntervalSinceReferenceDate / 12
            GeometryReader { proxy in
                ZStack {
                    Color(red: 0.22, green: 0.18, blue: 0.2)
                    if let image = ArtworkCache.shared.image(track?.artworkFilename) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.5).rotationEffect(.degrees(sin(phase) * 16))
                            .offset(x: sin(phase * 0.7) * 40, y: cos(phase * 0.8) * 60)
                            .blur(radius: 65, opaque: true).saturation(1.35)
                    }
                    Color.black.opacity(0.28)
                    LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct AirPlayButton: UIViewRepresentable {
    var white = false
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "音频输出与 AirPlay"
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = white ? .white.withAlphaComponent(0.75) : .label
        view.activeTintColor = UIColor(MusicDesign.accent)
    }
}

struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsRouteButton = false
        view.tintColor = .white.withAlphaComponent(0.75)
        view.setVolumeThumbImage(UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10)), for: .normal)
        view.accessibilityLabel = "系统音量"
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

struct MusicEmptyState: View {
    var title: String
    var message: String
    var symbol: String = "music.note"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: { Text(message) } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(MusicDesign.accent)
            }
        }
    }
}

struct TrackRow: View {
    let track: Track
    var subtitle: String? = nil
    var showArtwork = true
    var number: Int? = nil
    var action: () -> Void
    @Environment(PlayerStore.self) private var player
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if showArtwork { ArtworkView(track: track, radius: 5).frame(width: 48, height: 48) }
                else if let number { Text("\(number)").font(.subheadline).foregroundStyle(.secondary).frame(width: 24) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.body).foregroundStyle(player.current?.id == track.id ? MusicDesign.accent : .primary).lineLimit(1)
                    if showArtwork || subtitle != nil { Text(subtitle ?? track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if track.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(MusicDesign.accent) }
                if player.current?.id == track.id {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill").font(.caption).foregroundStyle(MusicDesign.accent)
                }
            }.frame(minHeight: showArtwork ? 54 : 44).contentShape(Rectangle())
        }.buttonStyle(PressStyle())
            .accessibilityLabel("\(track.title)，\(track.artist)")
    }
}

struct TrackActions: View {
    let track: Track
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    var body: some View {
        Button(track.isFavorite ? "取消收藏" : "收藏", systemImage: track.isFavorite ? "star.slash" : "star") { library.toggleFavorite(track.id) }
        Button("接下来播放", systemImage: "text.line.first.and.arrowtriangle.forward") { player.enqueue(track.id, next: true) }
        Button("最后播放", systemImage: "text.line.last.and.arrowtriangle.forward") { player.enqueue(track.id, next: false) }
        Menu("添加到歌单", systemImage: "text.badge.plus") {
            if library.playlists.isEmpty { Text("请先在资料库创建歌单") }
            ForEach(library.playlists) { playlist in
                Button(playlist.name) { library.add(track.id, to: playlist.id) }
            }
        }
        ShareLink(item: LibraryPaths.audio.appending(path: track.filename)) { Label("分享音频文件", systemImage: "square.and.arrow.up") }
    }
}
