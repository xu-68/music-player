import FlamingoCore
import SwiftUI
import UniformTypeIdentifiers

private enum ListeningPeriod: String, CaseIterable {
    case today = "今天", week = "本周", month = "本月", year = "今年", all = "全部"
    var component: Calendar.Component {
        switch self { case .today: return .day; case .week: return .weekOfYear; case .month: return .month; case .year: return .year; case .all: return .era }
    }
}
private struct ListeningRank: Identifiable {
    var id: String
    var name: String
    var subtitle: String
    var seconds: Double
    var plays: Int
    var tracks: [Track]
}
struct StatsView: View {
    var settingsAction: () -> Void
    @Environment(LibraryStore.self) private var library
    @AppStorage("statsPeriod") private var periodName = "本月"
    private var period: ListeningPeriod { ListeningPeriod(rawValue: periodName) ?? .month }
    private var sessions: [ListeningSession] {
        let recorded = library.snapshot.sessions
        if period == .all { return recorded }
        var calendar = Calendar.current; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        guard let interval = calendar.dateInterval(of: period.component, for: Date()) else { return [] }
        return recorded.filter { interval.contains($0.dayStart ?? $0.date) }
    }
    private var total: Double { sessions.reduce(0) { $0 + $1.seconds } }
    private func ranks(_ kind: Int) -> [ListeningRank] {
        var groups: [String: [ListeningSession]] = [:]
        for session in sessions {
            let track = library.track(session.trackID)
            let artists = session.artist ?? track?.artist ?? "未知艺人"
            let album = session.album ?? track?.album ?? "未知专辑"
            let keys: [String]
            if kind == 0 { keys = [session.trackID.uuidString] }
            else if kind == 1 {
                keys = artists.components(separatedBy: CharacterSet(charactersIn: AppPreferences.defaults.string(forKey: "artistSeparators") ?? ",")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else { keys = ["\(track?.albumArtist.isEmpty == false ? track!.albumArtist : artists)\u{1f}\(album)"] }
            for key in keys { groups[key, default: []].append(session) }
        }
        return groups.compactMap { key, events in
            guard let first = events.first else { return nil }
            let track = library.track(first.trackID)
            let ids = Set(events.map(\.trackID))
            return ListeningRank(id: key,
                name: kind == 0 ? first.title ?? track?.title ?? "已移除的歌曲" : kind == 1 ? key : first.album ?? track?.album ?? "未知专辑",
                subtitle: kind == 1 ? "\(ids.count) 首歌曲" : first.artist ?? track?.artist ?? "未知艺人",
                seconds: events.reduce(0) { $0 + $1.seconds }, plays: events.filter { $0.countsAsPlay == true }.count,
                tracks: library.tracks.filter { ids.contains($0.id) })
        }.sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ListeningPeriod.allCases, id: \.self) { value in
                            Button { periodName = value.rawValue } label: {
                                Text(value.rawValue).font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 10)
                                    .foregroundStyle(value == period ? MusicDesign.accent : Color.secondary)
                                    .overlay(Capsule().strokeBorder(value == period ? MusicDesign.accent : Color.secondary.opacity(0.12), lineWidth: 1.5))
                            }.buttonStyle(.plain).accessibilityAddTraits(value == period ? .isSelected : [])
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int(total / 60))").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("分钟 · \(period.rawValue)").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text("\(sessions.filter { $0.countsAsPlay == true }.count) 次播放 · \(Set(sessions.map(\.trackID)).count) 首歌曲 · \(ranks(2).count) 张专辑").font(.subheadline).foregroundStyle(.secondary)
                }
                if sessions.isEmpty {
                    MusicEmptyState(title: "每一次聆听，都算数", message: "与原版一致，歌曲播放进度达到一半后计入统计。", symbol: "chart.xyaxis.line").frame(minHeight: 260)
                } else {
                    rankSection("艺人", values: ranks(1))
                    rankSection("常听专辑", values: ranks(2))
                    rankSection("常听歌曲", values: ranks(0))
                }
            }.padding(20)
        }.navigationTitle("统计").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("设置", systemImage: "gearshape", action: settingsAction) } }
    }
    private func rankSection(_ title: String, values: [ListeningRank]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink { ListeningRankList(title: title, values: values) } label: {
                HStack { Text(title).font(.title2.bold()).foregroundStyle(Color.primary); Spacer(); Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.secondary) }
            }.buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(values.prefix(10))) { rank in
                        NavigationLink { SongsView(title: rank.name, ids: rank.tracks.map(\.id)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkView(track: rank.tracks.first).frame(width: 136, height: 136)
                                Text(rank.name).font(.body).foregroundStyle(Color.primary).lineLimit(1)
                                Text("\(Int(rank.seconds / 60)) 分钟").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(width: 136, alignment: .leading)
                        }.buttonStyle(PressStyle()).disabled(rank.tracks.isEmpty)
                    }
                }
            }
        }
    }
}
private struct ListeningRankList: View {
    var title: String
    var values: [ListeningRank]
    var body: some View {
        List(Array(values.enumerated()), id: \.element.id) { index, rank in ListeningRankRow(rank: rank, position: index + 1) }.listStyle(.plain).navigationTitle(title)
    }
}
private struct ListeningRankRow: View {
    var rank: ListeningRank
    var position: Int
    var body: some View {
        NavigationLink { SongsView(title: rank.name, ids: rank.tracks.map(\.id)) } label: {
            HStack(spacing: 12) {
                Text("\(position)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                ArtworkView(track: rank.tracks.first).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rank.name).font(.body).foregroundStyle(Color.primary).lineLimit(1)
                    Text(rank.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(rank.seconds / 60)) 分钟").font(.subheadline)
                    Text("\(rank.plays) 次播放").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.buttonStyle(.plain).disabled(rank.tracks.isEmpty)
    }
}
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerStore.self) private var player
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("animatedBackground") private var animatedBackground = false
    @AppStorage("lyricBlur") private var lyricBlur = false
    @AppStorage("lyricBalance") private var lyricBalance = false
    @AppStorage("lyricWeight") private var lyricWeight = "ExtraBold"
    @AppStorage("showTranslation") private var translation = true
    @AppStorage("showVolume") private var showVolume = true
    @AppStorage("barBlur") private var barBlur = false
    @AppStorage("playerCorner") private var corner = 30.0
    @AppStorage("animatedCovers") private var covers = false
    @AppStorage("artworkBlacklist") private var blacklist = ""
    @AppStorage("artistSeparators") private var artistSeparators = ","
    @AppStorage("autoScanMusic") private var refresh = true
    @AppStorage("fadePlayback") private var fade = true
    @AppStorage("listeningHistory") private var history = true
    @AppStorage("systemDecoderOnly") private var systemOnly = false
    @AppStorage("sleepFade") private var sleepFade = 5.0
    @State private var importing = false
    @State private var merge = true
    @State private var exportURL: URL?
    @State private var clearing = ""
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("显示模式", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Toggle("显示音量条", isOn: $showVolume)
                    Toggle("播放背景动画", isOn: $animatedBackground)
                    Toggle("栏背景模糊", isOn: $barBlur)
                    VStack(alignment: .leading) { Text("播放器收起圆角 · \(Int(corner))"); Slider(value: $corner, in: 0...60, step: 1) }
                }
                Section("歌词") {
                    Toggle("显示翻译（关闭后显示音译）", isOn: $translation)
                    Picker("字体粗细", selection: $lyricWeight) { ForEach(["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"], id: \.self) { Text($0).tag($0) } }
                    Toggle("平衡歌词换行", isOn: $lyricBalance)
                    Toggle("非当前歌词模糊", isOn: $lyricBlur)
                }
                Section {
                    Toggle("动态专辑封面", isOn: $covers)
                    NavigationLink("动态封面黑名单") { Form { Section("每行一个专辑名称") { TextEditor(text: $blacklist).frame(minHeight: 260) } }.navigationTitle("封面黑名单") }
                } header: { Text("动态封面") } footer: { Text("使用本地视频；支持在播放器菜单手动导入，或扫描文件夹内的 anim/专辑名.mp4。") }
                Section("资料库") {
                    LabeledContent("歌曲 / 专辑 / 歌单", value: "\(library.tracks.count) / \(library.albums.count) / \(library.playlists.count)")
                    Toggle("自动扫描媒体库", isOn: $refresh).accessibilityIdentifier("auto-scan-music")
                    Button("扫描媒体库", systemImage: "arrow.clockwise") { Task { await library.scanMusic() } }
                        .disabled(library.importing).accessibilityIdentifier("scan-music")
                    Text("在“文件 → 我的 iPhone → Flamingo → Music”中移入音乐文件，支持子文件夹。开启自动扫描后，启动或返回应用时更新媒体库。删除歌曲会同时删除此处的音乐文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("艺人拆分符号", text: $artistSeparators)
                }
                Section {
                    Toggle("播放 / 暂停淡入淡出", isOn: $fade)
                    Toggle("仅使用系统解码器", isOn: $systemOnly)
                    Picker("睡眠定时淡出", selection: $sleepFade) { ForEach([0.0, 5, 10, 30], id: \.self) { Text("\(Int($0)) 秒").tag($0) } }
                    NavigationLink("睡眠定时") { SleepTimerView() }
                } header: { Text("播放") } footer: { Text("自动模式下，系统不支持的格式通过 FFmpeg 转为本机 PCM 缓存播放，原文件保留用于分享。仅系统模式影响后续导入。") }
                Section {
                    Toggle("记录播放历史与统计", isOn: $history)
                    Button("导出统计 JSON", systemImage: "square.and.arrow.up") {
                        player.flushListening()
                        do { exportURL = try library.exportStatistics() } catch { library.errorMessage = error.localizedDescription }
                    }
                    if let exportURL { ShareLink("分享统计备份", item: exportURL) }
                    Button("导入并合并统计") { merge = true; importing = true }
                    Button("导入并覆盖统计") { merge = false; importing = true }
                    Button("清空统计", role: .destructive) { clearing = "统计"; confirmClear = true }
                    Button("清空最近播放", role: .destructive) { clearing = "最近播放"; confirmClear = true }
                } header: { Text("历史与备份") } footer: { Text("支持原版 Flamingo 统计 JSON。合并导入会按原始事件标识去重。") }
                Section("关于 Flamingo") {
                    LabeledContent("版本", value: "2.1.0 · iOS 原生重建")
                    Text("SwiftUI · UIKit · AVFoundation · FFmpeg。Xposed 状态栏歌词、Android 通知图标和 AudioTrack 参数为 Android 专属；iOS 使用系统锁屏控制、后台音频和 AirPlay。").font(.footnote).foregroundStyle(.secondary)
                    Link("原项目与源代码", destination: URL(string: "https://github.com/shouryadixitisverycool/Flamingo")!)
                    NavigationLink("开源许可") { LicenseView() }
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            do { try library.importStatistics(url, merge: merge) } catch { library.errorMessage = "统计导入失败：\(error.localizedDescription)" }
                        }
                    case .failure(let error): library.errorMessage = error.localizedDescription
                    }
                }
                .confirmationDialog("清空\(clearing)？", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("清空", role: .destructive) { if clearing == "统计" { player.clearStatistics() } else { library.clearHistory() } }
                } message: { Text("此操作无法撤销。请先导出需要保留的统计。") }
        }
    }
}

struct SleepTimerView: View {
    @Environment(PlayerStore.self) private var player
    @State private var mode = SleepMode.duration
    @State private var minutes = 30.0
    var body: some View {
        Form {
            if let plan = player.sleepPlan {
                Section("正在计时") {
                    LabeledContent("停止方式", value: plan.mode.rawValue)
                    if let deadline = plan.deadline {
                        HStack { Text("剩余时间"); Spacer(); Text(timerInterval: Date()...max(Date(), deadline), countsDown: true).monospacedDigit().accessibilityIdentifier("sleep-remaining") }
                        HStack { Button("延长 5 分钟") { player.extendSleepTimer(minutes: 5) }; Spacer(); Button("延长 15 分钟") { player.extendSleepTimer(minutes: 15) } }.buttonStyle(.borderless)
                    }
                    Button("取消定时", role: .destructive) { player.cancelSleepTimer() }
                }
            }
            Section("设置定时") {
                Picker("停止方式", selection: $mode) { ForEach(SleepMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                if mode == .duration { Stepper("\(Int(minutes)) 分钟", value: $minutes, in: 1...360, step: 1) }
                Button("开始定时") { player.setSleepTimer(mode: mode, minutes: minutes) }.accessibilityIdentifier("start-sleep-timer")
            }
        }.navigationTitle("睡眠定时").navigationBarTitleDisplayMode(.inline)
    }
}
private struct LicenseView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "GNU General Public License v3.0. 完整许可见源码根目录 LICENSE。" }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Flamingo iOS：GPL-3.0。FFmpeg 7.1.5：LGPL-2.1-or-later，未启用 GPL/非自由组件。完整可重现源码与编译脚本随仓库提供。")
                Link("FFmpeg 源码与许可", destination: URL(string: "https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz")!)
                Text(license).font(.system(.footnote, design: .monospaced))
            }.textSelection(.enabled).padding(20)
        }.navigationTitle("开源许可").navigationBarTitleDisplayMode(.inline)
    }
}
