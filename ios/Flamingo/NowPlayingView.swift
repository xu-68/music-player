import FlamingoCore
import SwiftUI
import UniformTypeIdentifiers

private enum PlayerPanel { case artwork, lyrics, queue }

struct NowPlayingView: View {
    var presentation: PlayerPresentation
    var sharedArtworkAvailable: Bool
    var safeArea: EdgeInsets
    var transitionTravel: CGFloat
    var close: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel = PlayerPanel.artwork
    @State private var importingLyrics = false
    @State private var lyricsTarget: UUID?
    @State private var importingVideo = false
    @State private var sleepSheet = false
    @State private var information = false
    @AppStorage("showVolume") private var showVolume = true

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                FlowingArtworkBackground(track: player.current, active: player.isPlaying && presentation.isPresented)
                VStack(spacing: 0) {
                    header.padding(.bottom, 4)
                    if landscape {
                        HStack(spacing: 36) {
                            primaryContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                            VStack(spacing: 20) { metadata; PlaybackProgressView(); transport; if showVolume { volume }; footer }.frame(maxWidth: 380)
                        }.padding(.horizontal, 40).padding(.bottom, 20)
                    } else {
                        let compact = proxy.size.height < 740
                        VStack(spacing: 0) {
                            if panel != .artwork {
                                metadata.padding(.top, 10).padding(.bottom, 18)
                            }
                            primaryContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom, panel == .artwork ? 24 : 14)
                            if panel == .artwork { metadata.padding(.bottom, 18) }
                            PlaybackProgressView().padding(.bottom, compact ? 6 : 18)
                            transport.frame(height: compact ? 76 : 104)
                                .padding(.bottom, compact ? 12 : 28)
                            if showVolume { volume.padding(.bottom, compact ? 10 : 20) }
                            footer.padding(.bottom, compact ? 8 : 22)
                        }.padding(.horizontal, 30)
                    }
                }.padding(.top, safeArea.top + 8).padding(.bottom, safeArea.bottom)
                    .frame(maxWidth: 1000).frame(maxWidth: .infinity)
                    .modifier(PlayerControlsReveal(progress: presentation.progress))
                    .accessibilityHidden(!presentation.isPresented)
            }.coordinateSpace(name: "player-content")
                .animation(reduceMotion ? nil : PlayerMotion.panel, value: panel)
                .foregroundStyle(.white).environment(\.colorScheme, .dark)
        }.accessibilityElement(children: .contain)
            .fileImporter(isPresented: $importingLyrics,
                          allowedContentTypes: [UTType(filenameExtension: "lrc") ?? .plainText, UTType(filenameExtension: "ttml") ?? .xml, .xml, .plainText]) { result in
                switch result {
                case .success(let url):
                    if let id = lyricsTarget { Task { await library.importLyrics(url, for: id); player.refreshLyrics() } }
                case .failure(let error): library.errorMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importingVideo, allowedContentTypes: [.movie, .mpeg4Movie]) { result in
                switch result {
                case .success(let url): if let id = lyricsTarget { Task { await library.importVideo(url, for: id) } }
                case .failure(let error): library.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $sleepSheet) { NavigationStack { SleepTimerView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sleepSheet = false } } } } }
            .sheet(isPresented: $information) { TrackInformationView(track: player.current) }
            .accessibilityAction(.escape, close)
    }
    private var header: some View {
        Button(action: close) {
            Capsule().fill(.white.opacity(0.35)).frame(width: 58, height: 4)
                .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("收起播放器").accessibilityIdentifier("close-player")
            .accessibilityValue(String(describing: presentation.phase))
            .highPriorityGesture(dismissGesture)
    }
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("player-root"))
            .onChanged { value in
                guard presentation.phase == .dragging || abs(value.translation.height) > abs(value.translation.width) else { return }
                presentation.drag(translation: value.translation.height, travel: transitionTravel)
            }
            .onEnded { value in
                presentation.endDrag(predictedTranslation: value.predictedEndTranslation.height,
                                     travel: transitionTravel, reduceMotion: reduceMotion)
            }
    }
    @ViewBuilder private var primaryContent: some View {
        switch panel {
        case .artwork:
            GeometryReader { geometry in
                let side = max(1, min(geometry.size.width, geometry.size.height))
                Group {
                    if reduceMotion {
                        AnimatedAlbumArtwork(track: player.current, active: player.isPlaying && presentation.isPresented)
                    } else {
                        ArtworkView(track: player.current, radius: 16)
                            .opacity(presentation.phase == .expanded && !sharedArtworkAvailable ? 1 : 0)
                    }
                }
                .frame(width: side, height: side)
                .background { GeometryReader { cover in
                    Color.clear.preference(key: PlayerArtworkFrameKey.self, value: cover.frame(in: .named("player-content")))
                } }
                .scaleEffect(reduceMotion || player.isPlaying ? 1 : 0.94)
                .animation(reduceMotion ? nil : PlayerMotion.artwork, value: player.isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle()).gesture(dismissGesture)
            }
        case .lyrics:
            LyricsView(isVisible: presentation.isPresented).transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
        case .queue:
            QueueView().transition(.opacity)
        }
    }
    private var metadata: some View {
        HStack(spacing: 12) {
            if panel != .artwork {
                ArtworkView(track: player.current, radius: 8)
                    .frame(width: 68, height: 68)
                    .opacity(reduceMotion || presentation.phase == .expanded && !sharedArtworkAvailable ? 1 : 0)
                    .background { GeometryReader { cover in
                        Color.clear.preference(key: PlayerArtworkFrameKey.self, value: cover.frame(in: .named("player-content")))
                    } }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "").font(panel == .artwork ? MusicTypography.title : MusicTypography.headline).lineLimit(1).minimumScaleFactor(0.7)
                Menu {
                    if let track = player.current {
                        ForEach(library.artists(for: track), id: \.self) { name in Button(name) { library.navigationTarget = .artist(name) } }
                    }
                } label: { Text(player.current?.artist ?? "").font(panel == .artwork ? MusicTypography.body : MusicTypography.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { if let track = player.current { library.toggleFavorite(track.id); PlayerHaptics.shared.discreteSelection() } } label: {
                Image(systemName: player.current?.isFavorite == true ? "star.fill" : "star")
                    .font(.system(size: 23, weight: .regular)).frame(width: 36, height: 44)
            }.buttonStyle(PressStyle()).accessibilityLabel(player.current?.isFavorite == true ? "取消收藏" : "收藏")
            Menu {
                if let track = player.current { TrackActions(track: track) }
                Button("导入歌词", systemImage: "text.bubble") { lyricsTarget = player.current?.id; importingLyrics = true }
                Button("导入动态封面", systemImage: "video") { lyricsTarget = player.current?.id; importingVideo = true }
                Button("睡眠定时", systemImage: "moon.zzz") { sleepSheet = true }
                Button("音频信息", systemImage: "info.circle") { information = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).frame(width: 36, height: 44)
            }.accessibilityLabel("更多播放选项")
        }
    }
    private var transport: some View {
        HStack(spacing: 0) {
            Button { if player.previous() { PlayerHaptics.shared.discreteSelection() } } label: { Image(systemName: "backward.fill").font(.system(size: 34)).frame(maxWidth: .infinity).frame(height: 64) }.accessibilityLabel("上一首").disabled(!player.canGoPrevious)
            Button(action: player.toggle) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 46)).frame(maxWidth: .infinity).frame(height: 64).contentTransition(reduceMotion ? .identity : .symbolEffect(.replace)) }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放").accessibilityIdentifier("player-play-pause")
            Button { if player.next() { PlayerHaptics.shared.discreteSelection() } } label: { Image(systemName: "forward.fill").font(.system(size: 34)).frame(maxWidth: .infinity).frame(height: 64) }.accessibilityLabel("下一首").disabled(!player.canGoNext)
        }.frame(maxWidth: .infinity).foregroundStyle(.white).buttonStyle(PressStyle())
    }
    private var volume: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill").font(MusicTypography.caption)
            AdaptiveSystemVolumeSlider(enabled: presentation.phase == .expanded && scenePhase == .active, trackID: player.current?.id).frame(height: 44)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 15))
        }.foregroundStyle(.white.opacity(0.5)).frame(height: 44)
    }
    private var footer: some View {
        HStack(spacing: 0) {
            Button { panel = panel == .lyrics ? .artwork : .lyrics } label: {
                Image(systemName: panel == .lyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(panel == .lyrics ? Color.black.opacity(0.65) : Color.white.opacity(0.65))
                    .frame(width: 38, height: 38)
                    .background(panel == .lyrics ? .white.opacity(0.65) : .clear, in: Circle())
                    .frame(width: 44, height: 44)
            }.frame(maxWidth: .infinity)
                .accessibilityLabel("歌词").accessibilityIdentifier("show-lyrics")
            AirPlayButton(white: true).frame(width: 44, height: 44).frame(maxWidth: .infinity)
            Button { panel = panel == .queue ? .artwork : .queue } label: {
                Image(systemName: "list.bullet").font(.system(size: 23, weight: .regular))
                    .foregroundStyle(panel == .queue ? Color.black.opacity(0.65) : Color.white.opacity(0.65))
                    .frame(width: 38, height: 38)
                    .background(panel == .queue ? .white.opacity(0.65) : .clear, in: Circle())
                    .frame(width: 44, height: 44)
            }.frame(maxWidth: .infinity)
                .accessibilityLabel("待播清单").accessibilityIdentifier("show-queue")
        }.buttonStyle(PressStyle())
    }
}

private struct PlaybackProgressView: View {
    @Environment(PlayerStore.self) private var player
    @State private var scrubbing: Double?
    @Environment(PlayerPresentation.self) private var presentation
    @Environment(\.scenePhase) private var scenePhase
    private var currentTime: Double { scrubbing ?? player.elapsed }
    var body: some View {
        VStack(spacing: 0) {
            AdaptiveProgressSlider(value: currentTime, total: player.duration, trackID: player.current?.id,
                                   enabled: presentation.phase == .expanded && scenePhase == .active,
                                   preview: { scrubbing = $0 },
                                   commit: { player.seek(to: $0); scrubbing = nil },
                                   cancelled: { scrubbing = nil })
                .frame(height: 44)
            HStack {
                Text(PlaybackTime.label(currentTime))
                Spacer()
                if player.current?.isLossless == true {
                    Label("无损", systemImage: "waveform").font(MusicTypography.tabLabel)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Text("−" + PlaybackTime.label(max(0, player.duration - currentTime)))
            }.font(MusicTypography.caption.weight(.medium)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
        }.onChange(of: player.current?.id) { _, _ in scrubbing = nil }
            .onChange(of: player.duration) { _, duration in if !duration.isFinite || duration <= 0 { scrubbing = nil } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { scrubbing = nil } }
            .onChange(of: presentation.phase) { _, phase in if phase != .expanded { scrubbing = nil } }
            .onDisappear { scrubbing = nil }
    }
}

struct LyricsView: View {
    var isVisible = true
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lyricBalance") private var balance = false
    @AppStorage("showTranslation") private var showTranslation = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var lyricSize = MusicTypography.lyricBaseSize
    @ScaledMetric(relativeTo: .largeTitle) private var lineSpacing = MusicTypography.lyricBaseSpacing
    @ScaledMetric(relativeTo: .largeTitle) private var paragraphSpacing = MusicTypography.lyricParagraphSpacing
    @State private var following = true
    @State private var lastScrollTarget: Int?
    @GestureState private var dragging = false
    private var activeIndex: Int? { LyricsParser.activeIndex(in: player.lines, at: player.elapsed) }
    private var activeLines: Set<Int> { LyricsParser.activeIndices(in: player.lines, at: player.elapsed) }
    var body: some View {
        let focused = activeLines
        Group {
            if !isVisible {
                Color.clear
            } else if player.lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                    Text("暂无歌词").font(MusicTypography.title)
                    Text("从右上角菜单导入 LRC 或 TTML 歌词").font(MusicTypography.subheadline).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: paragraphSpacing) {
                                ForEach(player.lines) { line in
                                    let active = focused.contains(line.id)
                                    Button {
                                        player.seek(to: line.start); following = true
                                        scroll(reader, to: line.id, force: true, seeking: true)
                                    } label: {
                                        LyricRowContent(line: line, active: active, balance: balance,
                                                        showTranslation: showTranslation, size: lyricSize,
                                                        lineSpacing: lineSpacing, reduceMotion: reduceMotion)
                                    }.buttonStyle(.plain).id(line.id)
                                        .accessibilityIdentifier("lyric-\(line.id)")
                                        .accessibilityLabel(line.text.isEmpty ? "间奏" : line.text)
                                        .accessibilityHint("跳到 \(PlaybackTime.label(line.start))")
                                }
                            }.padding(.top, proxy.size.height * 0.3).padding(.bottom, proxy.size.height * 0.65).padding(.horizontal, 4)
                        }.scrollIndicators(.hidden).accessibilityIdentifier("lyrics-scroll")
                            .mask { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                            .simultaneousGesture(DragGesture(minimumDistance: 3)
                                .updating($dragging) { _, state, _ in state = true }
                                .onChanged { _ in following = false })
                            .onChange(of: activeIndex) { old, index in
                                if following, !dragging, let index {
                                    scroll(reader, to: index, seeking: abs(index - (old ?? index)) > 1)
                                }
                            }
                            .onChange(of: player.lines, initial: true) { _, _ in
                                following = true; lastScrollTarget = nil
                                scroll(reader, to: activeIndex ?? player.lines.first?.id ?? 0, seeking: true)
                            }
                            .onChange(of: player.current?.id) { _, _ in
                                following = true; lastScrollTarget = nil
                                scroll(reader, to: activeIndex ?? player.lines.first?.id ?? 0, seeking: true)
                            }
                            .onChange(of: proxy.size) { _, _ in
                                if following, !dragging { scroll(reader, to: activeIndex ?? 0, force: true, seeking: true) }
                            }
                            .onChange(of: dynamicTypeSize) { _, _ in
                                if following, !dragging { scroll(reader, to: activeIndex ?? 0, force: true, seeking: true) }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if !following {
                                    Button { following = true; scroll(reader, to: activeIndex ?? 0, force: true) } label: { Label("跟随歌词", systemImage: "location.fill").font(.caption.bold()).padding(10).background(.regularMaterial, in: Capsule()) }.padding(.bottom, 5)
                                }
                            }
                    }
                }
            }
        }
    }
    private func scroll(_ reader: ScrollViewProxy, to id: Int, force: Bool = false, seeking: Bool = false) {
        guard !dragging, player.lines.contains(where: { $0.id == id }), force || lastScrollTarget != id else { return }
        lastScrollTarget = id
        let animation: Animation? = reduceMotion || seeking ? nil : MusicDesign.lyricSpring
        withAnimation(animation) { reader.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.32)) }
    }
}

private struct LyricRowContent: View {
    var line: LyricLine
    var active: Bool
    var balance: Bool
    var showTranslation: Bool
    var size: CGFloat
    var lineSpacing: CGFloat
    var reduceMotion: Bool
    @Environment(PlayerStore.self) private var player
    private var right: Bool { line.agent == "v2" }

    var body: some View {
        VStack(alignment: right ? .trailing : .leading, spacing: 8) {
            if !line.words.isEmpty {
                KaraokeLine(line: line, active: active, reduceMotion: reduceMotion,
                            balanced: balance, size: size, lineSpacing: lineSpacing, right: right)
            } else if line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                LyricCountdown(line: line, time: player.elapsed, active: active)
            } else {
                BalancedTextLayout(enabled: balance, right: right) {
                    Text(line.text).font(MusicTypography.lyric(size: size))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(.white.opacity(active ? 1 : 0.42))
                        .multilineTextAlignment(right ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showTranslation, let translation = line.translation, !translation.isEmpty {
                Text(translation).font(MusicTypography.subheadline)
                    .foregroundStyle(.white.opacity(active ? 0.8 : 0.4))
                    .multilineTextAlignment(right ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let transliteration = line.transliteration, !transliteration.isEmpty {
                Text(transliteration).font(MusicTypography.subheadline)
                    .foregroundStyle(.white.opacity(active ? 0.65 : 0.35))
                    .multilineTextAlignment(right ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: active)
    }
}

private struct BalancedTextLayout: Layout {
    var enabled: Bool
    var right: Bool
    private func width(_ available: CGFloat, view: LayoutSubview) -> CGFloat {
        guard enabled, view.sizeThatFits(.unspecified).width > available else { return available }
        let height = view.sizeThatFits(ProposedViewSize(width: available, height: nil)).height
        var low = available / 3, high = available
        for _ in 0..<10 {
            let mid = (low + high) / 2
            if view.sizeThatFits(ProposedViewSize(width: mid, height: nil)).height <= height + 0.5 { high = mid } else { low = mid }
        }
        return high
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let available = proposal.width ?? 320
        return CGSize(width: available, height: view.sizeThatFits(ProposedViewSize(width: width(available, view: view), height: nil)).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let measured = width(bounds.width, view: view)
        view.place(at: CGPoint(x: right ? bounds.maxX - measured : bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: measured, height: bounds.height))
    }
}

private struct LyricCountdown: View {
    var line: LyricLine
    var time: Double
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let progress = max(0, min(1, (time - line.start) / max(0.1, (line.end ?? line.start + 3) - line.start)))
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle().fill(.white.opacity(active && progress >= Double(i) / 3 ? 1 : 0.25))
                    .frame(width: 9, height: 9).scaleEffect(reduceMotion ? 1 : (active && progress >= Double(i) / 3 ? 1.12 : 0.8))
            }
        }.frame(height: 30).animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: progress).accessibilityLabel("间奏")
    }
}

private struct KaraokeLine: View {
    var line: LyricLine
    var active: Bool
    var reduceMotion: Bool
    var balanced: Bool
    var size: CGFloat
    var lineSpacing: CGFloat
    var right: Bool
    @Environment(PlayerStore.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlayerPresentation.self) private var presentation
    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.1 : nil,
                                paused: !active || !player.isPlaying || scenePhase != .active || !presentation.isPresented)) { _ in
            let time = player.lyricPlaybackTime
            LyricFlowLayout(balanced: balanced, lineSpacing: lineSpacing, right: right) {
                ForEach(Array(line.words.enumerated()), id: \.offset) { index, word in
                    let nextStart = index + 1 < line.words.count ? line.words[index + 1].start : line.end
                    let end = word.end ?? nextStart
                    let progress = highlightProgress(start: word.start, end: end, time: time)
                    Text(word.text).foregroundStyle(.white.opacity(active ? 0.4 : 0.42))
                        .lineSpacing(lineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .leading) {
                            Text(word.text).foregroundStyle(.white).lineSpacing(lineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                                .mask(alignment: .leading) {
                                    GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * progress) }
                                }
                        }
                        .transaction { $0.animation = nil }
                }
            }
            .font(MusicTypography.lyric(size: size))
        }.accessibilityElement(children: .ignore).accessibilityLabel(line.text)
    }

    private func highlightProgress(start: Double, end: Double?, time: Double) -> Double {
        guard active, time >= start else { return 0 }
        // An untimed word end is not a license to invent a karaoke duration.
        guard let end, end > start else { return 1 }
        return min(1, max(0, (time - start) / (end - start)))
    }
}

private struct LyricFlowLayout: Layout {
    var balanced = false
    var lineSpacing: CGFloat = 5
    var right = false
    struct Cache {
        var width: CGFloat?
        var spacing: CGFloat = 0
        var balanced = false
        var right = false
        var result: (CGSize, [CGPoint], [CGSize])?
    }
    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }
    private func cachedLayout(width: CGFloat, subviews: Subviews, cache: inout Cache) -> (CGSize, [CGPoint], [CGSize]) {
        if cache.width == width, cache.spacing == lineSpacing, cache.balanced == balanced,
           cache.right == right, let result = cache.result { return result }
        let result = layout(width: width, subviews: subviews)
        cache.width = width; cache.spacing = lineSpacing; cache.balanced = balanced
        cache.right = right; cache.result = result
        return result
    }
    private func layout(width: CGFloat, subviews: Subviews) -> (CGSize, [CGPoint], [CGSize]) {
        let width = max(1, width)
        let intrinsic = subviews.map { $0.sizeThatFits(.unspecified) }
        let measured = intrinsic.map(\.width)
        let total = measured.reduce(0, +)
        let longest = measured.max() ?? 0
        let available = balanced && total > width ? min(width, max(longest, total / ceil(total / max(1, width)) + 12)) : width
        var positions: [CGPoint] = [], sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = intrinsic[index].width <= width ? intrinsic[index] : subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > available { x = 0; y += rowHeight + lineSpacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y)); sizes.append(size)
            x += size.width; rowHeight = max(rowHeight, size.height)
        }
        if right {
            var start = 0
            while start < positions.count {
                var end = start + 1
                while end < positions.count && positions[end].y == positions[start].y { end += 1 }
                let trailing = positions[end - 1].x + sizes[end - 1].width
                for index in start..<end { positions[index].x += max(0, width - trailing) }
                start = end
            }
        }
        return (CGSize(width: width, height: y + rowHeight), positions, sizes)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        cachedLayout(width: proposal.width ?? 320, subviews: subviews, cache: &cache).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = cachedLayout(width: bounds.width, subviews: subviews, cache: &cache)
        for i in subviews.indices {
            let point = result.1[i]
            subviews[i].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: ProposedViewSize(result.2[i]))
        }
    }
}

struct QueueView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @State private var editMode = EditMode.inactive
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("待播清单").font(MusicTypography.title); Text("\(player.queue.upcoming.count) 首待播歌曲").font(MusicTypography.subheadline).foregroundStyle(.white.opacity(0.5)) }
                Spacer()
                Menu {
                    Button(editMode == .active ? "完成排序" : "调整顺序", systemImage: "arrow.up.arrow.down") { editMode = editMode == .active ? .inactive : .active }
                    Button("清空待播歌曲", role: .destructive) { player.clearUpcoming() }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 36) }
                Button { player.toggleShuffle(); PlayerHaptics.shared.discreteSelection() } label: {
                    Image(systemName: "shuffle").frame(width: 40, height: 36)
                        .background(player.queue.shuffled ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("随机播放").accessibilityValue(player.queue.shuffled ? "已开启" : "已关闭")
                Button { player.cycleRepeat(); PlayerHaptics.shared.discreteSelection() } label: {
                    Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat").frame(width: 40, height: 36)
                        .background(player.queue.repeatMode != .off ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("循环模式").accessibilityValue(player.queue.repeatMode == .off ? "关闭" : player.queue.repeatMode == .all ? "列表循环" : "单曲循环")
            }
            List {
                    if let current = player.current {
                        queueRow(current, current: true) {}.padding(.bottom, 16).listRowBackground(Color.clear)
                    }
                    if !player.queue.nextInQueue.isEmpty {
                        Section {
                            entries(player.queue.nextInQueue, start: player.queue.index + 1)
                        } header: {
                            HStack { Text("接下来播放"); Spacer(); Button("清空", action: player.clearNextInQueue).textCase(nil) }
                        }
                    }
                    Section("随后播放") {
                        entries(player.queue.upNext, start: player.queue.index + 1 + player.queue.nextInQueue.count)
                    }
            }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.editMode, $editMode)
                .scrollIndicators(.hidden)
        }
    }
    private func entries(_ entries: [QueueEntry], start: Int) -> some View {
        ForEach(entries) { entry in
            if let track = library.track(entry.trackID) {
                queueRow(track, current: false) { player.selectQueueEntry(entry.id) }
                    .contextMenu {
                        if entry.requested != true { Button("移至下一首", systemImage: "text.line.first.and.arrowtriangle.forward") { player.moveQueueEntryNext(entry.id) } }
                        Button("移除", role: .destructive) { player.removeQueueEntry(entry.id) }
                    }
                    .swipeActions(edge: .leading) {
                        if entry.requested != true { Button("下一首") { player.moveQueueEntryNext(entry.id) }.tint(MusicDesign.accent) }
                    }.listRowBackground(Color.clear)
            }
        }.onDelete { offsets in
            let ids = offsets.map { entries[$0].id }; for id in ids { player.removeQueueEntry(id) }
        }.onMove { offsets, destination in
            player.moveQueueEntries(from: IndexSet(offsets.map { $0 + start }), to: destination + start)
        }
    }
    private func queueRow(_ track: Track, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ArtworkView(track: track, radius: 5).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(MusicTypography.headline).lineLimit(1)
                    Text(current ? "正在播放 · \(track.artist)" : track.artist).font(MusicTypography.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if current { Image(systemName: "waveform").foregroundStyle(.white.opacity(0.7)) }
            }.padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(current)
    }
}

private struct TrackInformationView: View {
    var track: Track?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                if let track {
                    Section("标签") { LabeledContent("标题", value: track.title); LabeledContent("艺人", value: track.artist); LabeledContent("专辑", value: track.album) }
                    Section("音频") {
                        LabeledContent("文件", value: track.originalFilename ?? track.filename)
                        LabeledContent("解码", value: track.decodedFilename == nil ? "系统" : "FFmpeg → PCM")
                        LabeledContent("编码", value: track.codec ?? (track.filename as NSString).pathExtension.uppercased())
                        if let rate = track.sampleRate { LabeledContent("采样率", value: "\(String(format: "%.1f", rate / 1000)) kHz") }
                        if let bits = track.bitsPerSample, bits > 0 { LabeledContent("位深", value: "\(bits) bit") }
                        if let bitrate = track.bitRate, bitrate > 0 { LabeledContent("码率", value: "\(bitrate / 1000) kbps") }
                        LabeledContent("时长", value: PlaybackTime.label(track.duration))
                    }
                }
            }.navigationTitle("音频信息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
