import AVFoundation
import QuartzCore
import FlamingoCore
import SwiftUI

struct AnimatedAlbumArtwork: View {
    var track: Track?
    var active: Bool
    var fullBleed = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("animatedCovers") private var enabled = false
    @AppStorage("artworkBlacklist") private var blacklist = ""
    private var allowed: Bool {
        enabled && !reduceMotion && !blacklist.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.contains(track?.album ?? "")
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = ArtworkCache.shared.image(track?.artworkFilename) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .id(track?.artworkFilename).transition(.opacity)
                } else {
                    ArtworkView(track: track, radius: 0)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                .animation(reduceMotion ? nil : PlayerMotion.panel, value: track?.artworkFilename)
        }
            .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : 16, style: .continuous))
            .overlay {
                if allowed, let name = track?.videoFilename {
                    LoopingVideo(url: LibraryPaths.video.appending(path: name), playing: active && phase == .active)
                        .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : 16, style: .continuous))
                }
            }
    }
}

private final class VideoLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
private struct LoopingVideo: UIViewRepresentable {
    var url: URL
    var playing: Bool
    final class Coordinator {
        var url: URL?
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        var readiness: NSKeyValueObservation?
        var playing = false
        init() { player.isMuted = true; player.allowsExternalPlayback = false; player.preventsDisplaySleepDuringVideoPlayback = false }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> VideoLayerView {
        let view = VideoLayerView(); view.videoLayer.videoGravity = .resizeAspectFill
        view.videoLayer.player = context.coordinator.player
        view.isOpaque = false
        view.videoLayer.opacity = 0
        context.coordinator.readiness = view.videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak view] layer, _ in
            let ready = layer.isReadyForDisplay
            DispatchQueue.main.async { [weak view] in
                CATransaction.begin(); CATransaction.setDisableActions(true)
                view?.videoLayer.opacity = ready ? 1 : 0
                CATransaction.commit()
            }
        }
        return view
    }
    func updateUIView(_ view: VideoLayerView, context: Context) {
        let controller = context.coordinator
        let changedURL = controller.url != url
        if changedURL {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            view.videoLayer.opacity = 0
            CATransaction.commit()
            controller.player.pause(); controller.looper?.disableLooping(); controller.player.removeAllItems()
            controller.url = url
            controller.looper = AVPlayerLooper(player: controller.player, templateItem: AVPlayerItem(url: url))
        }
        if changedURL || controller.playing != playing {
            controller.playing = playing
            if playing { controller.player.play() } else { controller.player.pause() }
        }
    }
    static func dismantleUIView(_ view: VideoLayerView, coordinator: Coordinator) {
        coordinator.readiness?.invalidate()
        coordinator.player.pause(); coordinator.looper?.disableLooping(); coordinator.player.removeAllItems()
        view.videoLayer.player = nil
    }
}
