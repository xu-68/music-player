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

struct ArtworkTint: View {
    var track: Track?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let image = ArtworkCache.shared.image(track?.artworkFilename) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).blur(radius: 30)
                }
                Color.black.opacity(0.65)
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

// Local cover light gives glass a real colored surface to sample, even on an empty library page.
struct DockArtworkGlow: View {
    var track: Track?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { proxy in
            if let image = ArtworkCache.shared.image(track?.artworkFilename) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 45).saturation(1.3).opacity(scheme == .dark ? 0.3 : 0.18)
                    .mask { LinearGradient(colors: [.clear, .black.opacity(0.35), .black], startPoint: .top, endPoint: .bottom) }
                    .clipped()
            }
        }
    }
}

// UIKit's public material API supplies adaptive backdrop blur and saturation.
// It deliberately avoids private filters with undocumented radius controls.
struct PlayerGlassSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        view.contentView.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}

struct FlowingArtworkBackground: View {
    var track: Track?
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("animatedBackground") private var animated = true
    @State private var colors: [Color] = [.init(red: 0.3, green: 0.35, blue: 0.38), .init(red: 0.15, green: 0.2, blue: 0.23), .init(red: 0.4, green: 0.33, blue: 0.3)]
    @State private var elapsed: TimeInterval = 0
    @State private var lastTick: Date?
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active || reduceMotion || !animated || scenePhase != .active)) { context in
            let phase = reduceMotion || !animated ? 0 : elapsed / 12
            GeometryReader { proxy in
                // Extend the entire render surface beyond the viewport before blurring.
                // Transparent blur edges stay outside the screen instead of forming seams.
                ZStack {
                    colors[1]
                    Ellipse().fill(colors[0])
                        .frame(width: proxy.size.width * 1.45, height: proxy.size.height * 0.8)
                        .offset(x: -proxy.size.width * 0.3 + sin(phase * 0.7) * 90,
                                y: -proxy.size.height * 0.3 + cos(phase) * 80)
                    Ellipse().fill(colors[2])
                        .frame(width: proxy.size.width * 1.5, height: proxy.size.height * 0.75)
                        .offset(x: proxy.size.width * 0.35 + cos(phase * 0.8) * 100,
                                y: proxy.size.height * 0.3 + sin(phase) * 90)
                    Circle().fill(colors[0].opacity(0.65))
                        .frame(width: proxy.size.width * 0.9)
                        .offset(x: sin(phase * 0.6) * 80, y: proxy.size.height * 0.1)
                }.frame(width: proxy.size.width + 480, height: proxy.size.height + 480)
                    .compositingGroup().blur(radius: 120)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay { Color.black.opacity(0.2) }.clipped()
            }
            .onChange(of: context.date) { previous, now in
                if active && animated && !reduceMotion && scenePhase == .active {
                    // Clamp the interval so resuming never jumps to a new mesh position.
                    elapsed += min(0.1, max(0, now.timeIntervalSince(lastTick ?? previous)))
                }
                lastTick = now
            }
        }.task(id: track?.artworkFilename) {
            colors = ArtworkPalette.colors(from: ArtworkCache.shared.image(track?.artworkFilename))
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private enum ArtworkPalette {
    static func colors(from image: UIImage?) -> [Color] {
        let fallback: [Color] = [.init(red: 0.3, green: 0.35, blue: 0.38), .init(red: 0.15, green: 0.2, blue: 0.23), .init(red: 0.4, green: 0.33, blue: 0.3)]
        guard let source = image?.cgImage else { return fallback }
        // Read a tiny thumbnail only when the cover changes, never in the animation loop.
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        guard drawn else { return fallback }
        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let light = 0.2126 * r + 0.7152 * g + 0.0722 * b
            guard pixels[i + 3] > 200, light > 0.06, light < 0.92 else { continue }
            let key = (Int(r * 7) << 6) | (Int(g * 7) << 3) | Int(b * 7)
            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
        }
        // Favor colors that occupy real area AND carry chroma; a flat gray must not
        // crowd out both the blue cover background and warm skin/lettering colors.
        let ranked = buckets.values.sorted { lhs, rhs in
            func score(_ value: (count: Int, r: Double, g: Double, b: Double)) -> Double {
                let n = Double(value.count)
                let chroma = (max(value.r, max(value.g, value.b)) - min(value.r, min(value.g, value.b))) / n
                return sqrt(n) * (0.12 + chroma * 3)
            }
            return score(lhs) > score(rhs)
        }
        guard let dominant = ranked.first else { return fallback }
        let count = Double(dominant.count)
        let primary = (dominant.r / count, dominant.g / count, dominant.b / count)
        let secondary = ranked.dropFirst().max { lhs, rhs in
            func distance(_ value: (count: Int, r: Double, g: Double, b: Double)) -> Double {
                let n = Double(value.count)
                let chroma = (max(value.r, max(value.g, value.b)) - min(value.r, min(value.g, value.b))) / n
                return (abs(value.r / n - primary.0) + abs(value.g / n - primary.1) + abs(value.b / n - primary.2)) * sqrt(n) * (0.15 + chroma * 3)
            }
            return distance(lhs) < distance(rhs)
        }
        let accent: (Double, Double, Double)
        if let secondary {
            let n = Double(secondary.count)
            accent = (secondary.r / n, secondary.g / n, secondary.b / n)
        } else { accent = (primary.0 * 0.5, primary.1 * 0.5, primary.2 * 0.5) }
        func tinted(_ rgb: (Double, Double, Double), brightness: CGFloat) -> Color {
            let source = UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
            source.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
            return Color(uiColor: UIColor(hue: hue, saturation: min(0.8, saturation * 1.3), brightness: brightness, alpha: 1))
        }
        return [tinted(primary, brightness: 0.62), tinted(primary, brightness: 0.22), tinted(accent, brightness: 0.48)]
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
        // The reference has a continuous capsule track with no visible thumb.
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        view.setVolumeThumbImage(thumb, for: .normal)
        func track(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 12, height: 6)).image { _ in
                color.setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 12, height: 6), cornerRadius: 3).fill()
            }.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3))
        }
        view.setMinimumVolumeSliderImage(track(.white.withAlphaComponent(0.8)), for: .normal)
        view.setMaximumVolumeSliderImage(track(.white.withAlphaComponent(0.22)), for: .normal)
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
        Button("添加到歌单", systemImage: "text.badge.plus") { library.playlistAddition = PlaylistAddition(trackIDs: [track.id]) }
        Menu("前往艺人", systemImage: "music.mic") {
            ForEach(library.artists(for: track), id: \.self) { name in Button(name) { library.navigationTarget = .artist(name) } }
        }
        Button("前往专辑", systemImage: "square.stack") { library.navigationTarget = .album(track.albumKey) }
        ShareLink(item: LibraryPaths.audio.appending(path: track.filename)) { Label("分享音频文件", systemImage: "square.and.arrow.up") }
    }
}
