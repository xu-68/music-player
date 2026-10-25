import AVFoundation
import FlamingoCore
import SwiftUI

actor AnimatedArtworkService {
    static let shared = AnimatedArtworkService()
    private let directory = URL.cachesDirectory.appending(path: "AnimatedArtwork", directoryHint: .isDirectory)
    func size() -> Int64 {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        } ?? 0
    }
    func clear() { try? FileManager.default.removeItem(at: directory) }
}

struct AnimatedAlbumArtwork: View {
    var track: Track?
    var active: Bool
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("animatedCovers") private var enabled = false
    @AppStorage("artworkBlacklist") private var blacklist = ""
    private var allowed: Bool {
        enabled && !reduceMotion && !blacklist.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.contains(track?.album ?? "")
    }
    var body: some View {
        ArtworkView(track: track, radius: 10)
            .overlay {
                if allowed, let name = track?.videoFilename {
                    LoopingVideo(url: LibraryPaths.video.appending(path: name), playing: active && phase == .active)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        init() { player.isMuted = true; player.allowsExternalPlayback = false }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> VideoLayerView {
        let view = VideoLayerView(); view.videoLayer.videoGravity = .resizeAspectFill
        view.videoLayer.player = context.coordinator.player; return view
    }
    func updateUIView(_ view: VideoLayerView, context: Context) {
        let controller = context.coordinator
        if controller.url != url {
            controller.player.pause(); controller.looper?.disableLooping(); controller.player.removeAllItems()
            controller.url = url
            controller.looper = AVPlayerLooper(player: controller.player, templateItem: AVPlayerItem(url: url))
        }
        if playing { controller.player.play() } else { controller.player.pause() }
    }
    static func dismantleUIView(_ view: VideoLayerView, coordinator: Coordinator) {
        coordinator.player.pause(); coordinator.looper?.disableLooping(); coordinator.player.removeAllItems()
        view.videoLayer.player = nil
    }
}
