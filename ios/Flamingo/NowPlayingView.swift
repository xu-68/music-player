import FlamingoCore
import SwiftUI
import UniformTypeIdentifiers

private enum PlayerPanel { case artwork, lyrics, queue }

struct NowPlayingView: View {
    var namespace: Namespace.ID
    var safeArea: EdgeInsets
    var close: () -> Void
    @Environment(PlayerStore.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel = PlayerPanel.artwork
    @State private var drag: CGFloat = 0
    @State private var importingLyrics = false
    @State private var lyricsTarget: UUID?
    @State private var importingVideo = false
    @State private var sleepSheet = false
    @State private var information = false
    @AppStorage("showVolume") private var showVolume = true
    @AppStorage("playerCorner") private var corner = 30.0

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                FlowingArtworkBackground(track: player.current, active: player.isPlaying)
                VStack(spacing: 0) {
                    header.padding(.bottom, 4)
                    if landscape {
                        HStack(spacing: 36) {
                            primaryContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                            VStack(spacing: 20) { metadata; PlaybackProgressView(); transport; volume; footer }.frame(maxWidth: 380)
                        }.padding(.horizontal, 40).padding(.bottom, 20)
                    } else {
                        VStack(spacing: 0) {
                            primaryContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom, panel == .artwork ? 20 : 12)
                            metadata.padding(.bottom, 10)
                            PlaybackProgressView().padding(.bottom, 12)
                            transport.padding(.bottom, proxy.size.height < 700 ? 12 : 20)
                            if showVolume { volume.padding(.bottom, 8) }
                            footer.padding(.bottom, 4)
                        }.padding(.horizontal, 30)
                    }
                }.padding(.top, safeArea.top + 8).padding(.bottom, safeArea.bottom)
                    .frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }.clipShape(RoundedRectangle(cornerRadius: drag > 0 ? corner : 0, style: .continuous))
                .offset(y: drag).scaleEffect(reduceMotion ? 1 : 1 - min(drag / 5000, 0.06), anchor: .bottom)
                .animation(reduceMotion ? nil : MusicDesign.spring, value: panel)
                .foregroundStyle(.white).preferredColorScheme(.dark)
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
            .sensoryFeedback(.selection, trigger: panel)
            .accessibilityAction(.escape, close)
    }
    private var header: some View {
        Button(action: close) {
            Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("收起播放器").accessibilityIdentifier("close-player")
            .simultaneousGesture(dismissGesture)
    }
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in if value.translation.height > 0 { drag = value.translation.height } }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 240 { close() }
                else { withAnimation(MusicDesign.spring) { drag = 0 } }
            }
    }
    @ViewBuilder private var primaryContent: some View {
        switch panel {
        case .artwork:
            GeometryReader { proxy in
                let side = max(80, min(proxy.size.width, proxy.size.height))
                AnimatedAlbumArtwork(track: player.current, active: player.isPlaying)
                    .matchedGeometryEffect(id: "player-artwork", in: namespace)
                    .frame(width: side, height: side)
                    .scaleEffect(player.isPlaying ? 1 : 0.83)
                    .shadow(color: .black.opacity(player.isPlaying ? 0.28 : 0.18), radius: player.isPlaying ? 24 : 12, y: player.isPlaying ? 18 : 10)
                    .animation(reduceMotion ? nil : player.isPlaying ? MusicDesign.spring : .timingCurve(0.16, 1, 0.3, 1, duration: 0.35), value: player.isPlaying)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.gesture(dismissGesture)
        case .lyrics:
            LyricsView().transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.98)))
        case .queue:
            QueueView().transition(.opacity)
        }
    }
    private var metadata: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.current?.title ?? "").font(.system(size: 23, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(player.current?.artist ?? "").font(.system(size: 21)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { if let track = player.current { library.toggleFavorite(track.id) } } label: {
                Image(systemName: player.current?.isFavorite == true ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold)).frame(width: 34, height: 44)
            }.buttonStyle(PressStyle()).accessibilityLabel(player.current?.isFavorite == true ? "取消收藏" : "收藏")
            Menu {
                if let track = player.current { TrackActions(track: track) }
                Button("导入歌词", systemImage: "text.bubble") { lyricsTarget = player.current?.id; importingLyrics = true }
                Button("导入动态封面", systemImage: "video") { lyricsTarget = player.current?.id; importingVideo = true }
                Button("睡眠定时", systemImage: "moon.zzz") { sleepSheet = true }
                Button("音频信息", systemImage: "info.circle") { information = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).frame(width: 32, height: 32)
                    .background(.white.opacity(0.12), in: Circle()).frame(width: 44, height: 44)
            }.accessibilityLabel("更多播放选项")
        }
    }
    private var transport: some View {
        HStack {
            Spacer()
            Button(action: player.previous) { Image(systemName: "backward.fill").font(.system(size: 31)).frame(width: 64, height: 58) }.accessibilityLabel("上一首")
            Spacer()
            Button(action: player.toggle) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 43)).frame(width: 70, height: 62).contentTransition(.symbolEffect(.replace)) }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放").accessibilityIdentifier("player-play-pause")
            Spacer()
            Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 31)).frame(width: 64, height: 58) }.accessibilityLabel("下一首")
            Spacer()
        }.buttonStyle(PressStyle())
    }
    private var volume: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.fill").font(.system(size: 13))
            SystemVolumeSlider().frame(height: 30).padding(.top, 4)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 15))
        }.foregroundStyle(.white.opacity(0.5)).frame(height: 35)
    }
    private var footer: some View {
        HStack {
            Button { panel = panel == .lyrics ? .artwork : .lyrics } label: {
                Image(systemName: "quote.bubble").font(.system(size: 21)).frame(width: 46, height: 40)
                    .background(panel == .lyrics ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.accessibilityLabel("歌词").accessibilityIdentifier("show-lyrics")
            Spacer()
            AirPlayButton(white: true).frame(width: 48, height: 44)
            Spacer()
            Button { panel = panel == .queue ? .artwork : .queue } label: {
                Image(systemName: "list.bullet").font(.system(size: 22)).frame(width: 46, height: 40)
                    .background(panel == .queue ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }.accessibilityLabel("待播清单").accessibilityIdentifier("show-queue")
        }.foregroundStyle(.white.opacity(0.72)).buttonStyle(PressStyle())
    }
}

private struct PlaybackProgressView: View {
    @Environment(PlayerStore.self) private var player
    @State private var scrubbing: Double?
    private var currentTime: Double { scrubbing ?? player.elapsed }
    var body: some View {
        VStack(spacing: 0) {
            ProgressScrubber(value: currentTime, total: player.duration,
                             changed: { scrubbing = $0 }, ended: { player.seek(to: $0); scrubbing = nil })
            HStack {
                Text(PlaybackTime.label(currentTime))
                Spacer()
                if player.current?.isLossless == true {
                    Label("无损", systemImage: "waveform").font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Text("−" + PlaybackTime.label(max(0, player.duration - currentTime)))
            }.font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
        }.onChange(of: player.current?.id) { _, _ in scrubbing = nil }
    }
}

private struct ProgressScrubber: View {
    var value: Double
    var total: Double
    var changed: (Double) -> Void
    var ended: (Double) -> Void
    @State private var touching = false
    private var fraction: Double { total > 0 ? min(max(value / total, 0), 1) : 0 }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white.opacity(touching ? 0.95 : 0.5)).frame(width: max(4, proxy.size.width * fraction))
            }.frame(height: touching ? 9 : 4).frame(maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { event in touching = true; changed(min(max(0, event.location.x / max(proxy.size.width, 1)), 1) * total) }
                    .onEnded { event in touching = false; ended(min(max(0, event.location.x / max(proxy.size.width, 1)), 1) * total) })
                .animation(.easeOut(duration: 0.15), value: touching)
        }.frame(height: 28).accessibilityElement().accessibilityLabel("播放进度")
            .accessibilityIdentifier("playback-progress")
            .accessibilityValue("\(PlaybackTime.label(value))，总时长 \(PlaybackTime.label(total))")
            .accessibilityAdjustableAction { direction in ended(min(max(0, value + (direction == .increment ? 10 : -10)), total)) }
    }
}

struct LyricsView: View {
    @Environment(PlayerStore.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lyricBlur") private var blur = false
    @AppStorage("showTranslation") private var translation = true
    @AppStorage("lyricWeight") private var weight = "ExtraBold"
    @AppStorage("lyricBalance") private var balance = false
    @State private var following = true
    private var activeIndex: Int? { LyricsParser.activeIndex(in: player.lines, at: player.elapsed) }
    private var activeLines: Set<Int> { LyricsParser.activeIndices(in: player.lines, at: player.elapsed) }
    var body: some View {
        Group {
            if player.lines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
                    Text("暂无歌词").font(.title2.bold())
                    Text("从右上角菜单导入 LRC 或 TTML 歌词").font(.subheadline).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    GeometryReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 26) {
                                ForEach(player.lines) { line in
                                    let active = activeLines.contains(line.id)
                                    let right = line.agent == "v2"
                                    Button {
                                        player.seek(to: line.start); following = true
                                        scroll(reader, to: line.id)
                                    } label: {
                                        VStack(alignment: right ? .trailing : .leading, spacing: 8) {
                                            if line.words.isEmpty {
                                                if line.text.isEmpty {
                                                    LyricCountdown(line: line, time: player.elapsed, active: active)
                                                } else { Text(line.text)
                                                    .font(.system(size: 30, weight: PlayerPreferences.lyricWeight)).tracking(-0.5)
                                                    .foregroundStyle(.white.opacity(active ? 1 : 0.26))
                                                    .multilineTextAlignment(right ? .trailing : .leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                }
                                            } else {
                                                KaraokeLine(line: line, time: player.elapsed, active: active, reduceMotion: reduceMotion, balanced: balance, weight: weight)
                                            }
                                            if let secondary = translation ? line.translation : line.transliteration { Text(secondary).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white.opacity(active ? 0.8 : 0.3)) }
                                        }.frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
                                            .scaleEffect(active && !reduceMotion ? 1 : 0.97, anchor: right ? .trailing : .leading)
                                            .blur(radius: !following || !blur || reduceMotion || activeIndex == nil ? 0 : min(2.5, Double(abs(line.id - (activeIndex ?? 0))) * 0.65))
                                    }.buttonStyle(.plain).id(line.id)
                                        .accessibilityIdentifier("lyric-\(line.id)")
                                        .accessibilityLabel(line.text + (line.translation.map { "，" + $0 } ?? ""))
                                        .accessibilityHint("跳到 \(PlaybackTime.label(line.start))")
                                }
                            }.padding(.top, proxy.size.height * 0.3).padding(.bottom, proxy.size.height * 0.65).padding(.horizontal, 4)
                        }.scrollIndicators(.hidden).accessibilityIdentifier("lyrics-scroll")
                            .mask { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08), .init(color: .black, location: 0.86), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in following = false })
                            .onChange(of: activeIndex) { _, index in if following, let index { scroll(reader, to: index) } }
                            .onChange(of: player.current?.id) { _, _ in following = true; scroll(reader, to: activeIndex ?? 0) }
                            .onAppear { scroll(reader, to: activeIndex ?? 0) }
                            .overlay(alignment: .bottomTrailing) {
                                if !following {
                                    Button { following = true; scroll(reader, to: activeIndex ?? 0) } label: { Label("跟随歌词", systemImage: "location.fill").font(.caption.bold()).padding(10).background(.regularMaterial, in: Capsule()) }.padding(.bottom, 5)
                                }
                            }
                    }
                }
            }
        }
    }
    private func scroll(_ reader: ScrollViewProxy, to id: Int) {
        withAnimation(reduceMotion ? nil : MusicDesign.lyricSpring) { reader.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.32)) }
    }
}

private struct LyricCountdown: View {
    var line: LyricLine
    var time: Double
    var active: Bool
    var body: some View {
        let progress = max(0, min(1, (time - line.start) / max(0.1, (line.end ?? line.start + 3) - line.start)))
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle().fill(.white.opacity(active && progress >= Double(i) / 3 ? 1 : 0.25))
                    .frame(width: 9, height: 9).scaleEffect(active && progress >= Double(i) / 3 ? 1.12 : 0.8)
            }
        }.frame(height: 30).animation(.easeInOut(duration: 0.18), value: progress).accessibilityLabel("间奏")
    }
}

private struct KaraokeLine: View {
    var line: LyricLine
    var time: Double
    var active: Bool
    var reduceMotion: Bool
    var balanced: Bool
    var weight: String
    var body: some View {
        LyricFlowLayout(balanced: balanced) {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                let end = word.end ?? line.end ?? word.start + 0.5
                let progress = active ? min(1, max(0, (time - word.start) / max(0.01, end - word.start))) : 0
                Text(word.text).foregroundStyle(.white.opacity(active ? 0.35 : 0.26))
                    .overlay(alignment: .leading) {
                        Text(word.text).foregroundStyle(.white).mask(alignment: .leading) {
                            GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * progress) }
                        }
                    }
                    .offset(y: !reduceMotion && active && progress > 0 && progress < 1 ? -1.5 : 0)
                    .animation(reduceMotion ? nil : .linear(duration: 0.1), value: progress)
            }
        }.font(.system(size: 30, weight: PlayerPreferences.lyricWeight)).accessibilityElement(children: .ignore).accessibilityLabel(line.text)
    }
}

private struct LyricFlowLayout: Layout {
    var balanced = false
    private func layout(width: CGFloat, subviews: Subviews) -> (CGSize, [CGPoint], [CGSize]) {
        let measured = subviews.map { $0.sizeThatFits(.unspecified).width }
        let total = measured.reduce(0, +)
        let longest = measured.max() ?? 0
        let available = balanced && total > width ? min(width, max(longest, total / ceil(total / max(1, width)) + 12)) : width
        var positions: [CGPoint] = [], sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > available { x = 0; y += rowHeight + 2; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y)); sizes.append(size)
            x += size.width; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions, sizes)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width ?? 320, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
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
                VStack(alignment: .leading, spacing: 4) { Text("待播清单").font(.title2.bold()); Text("\(player.queue.upcoming.count) 首待播歌曲").font(.subheadline).foregroundStyle(.white.opacity(0.5)) }
                Spacer()
                Menu {
                    Button(editMode == .active ? "完成排序" : "调整顺序", systemImage: "arrow.up.arrow.down") { editMode = editMode == .active ? .inactive : .active }
                    Button("清空待播歌曲", role: .destructive) { player.clearUpcoming() }
                } label: { Image(systemName: "ellipsis").frame(width: 32, height: 36) }
                Button(action: player.toggleShuffle) {
                    Image(systemName: "shuffle").frame(width: 40, height: 36)
                        .background(player.queue.shuffled ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("随机播放").accessibilityValue(player.queue.shuffled ? "已开启" : "已关闭")
                Button(action: player.cycleRepeat) {
                    Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat").frame(width: 40, height: 36)
                        .background(player.queue.repeatMode != .off ? .white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.accessibilityLabel("循环模式").accessibilityValue(player.queue.repeatMode == .off ? "关闭" : player.queue.repeatMode == .all ? "列表循环" : "单曲循环")
            }
            List {
                    if let current = player.current {
                        queueRow(current, current: true) {}.padding(.bottom, 16).listRowBackground(Color.clear)
                    }
                    ForEach(player.queue.upcoming) { entry in
                        if let track = library.track(entry.trackID) {
                            HStack {
                                queueRow(track, current: false) { player.selectQueueEntry(entry.id) }
                            }.contextMenu {
                                Button("移至下一首", systemImage: "text.line.first.and.arrowtriangle.forward") { player.moveQueueEntryNext(entry.id) }
                                Button("移除", role: .destructive) { player.removeQueueEntry(entry.id) }
                            }.swipeActions(edge: .leading) { Button("下一首") { player.moveQueueEntryNext(entry.id) }.tint(MusicDesign.accent) }
                                .listRowBackground(Color.clear)
                        }
                    }.onDelete { offsets in
                        let ids = offsets.map { player.queue.upcoming[$0].id }
                        for id in ids { player.removeQueueEntry(id) }
                    }.onMove { offsets, destination in
                        let start = player.queue.index + 1
                        player.moveQueueEntries(from: IndexSet(offsets.map { $0 + start }), to: destination + start)
                    }
            }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.editMode, $editMode)
                .scrollIndicators(.hidden)
        }
    }
    private func queueRow(_ track: Track, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ArtworkView(track: track, radius: 5).frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                    Text(current ? "正在播放 · \(track.artist)" : track.artist).font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
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
