import FlamingoCore
import SwiftUI

private enum ListeningPeriod: String, CaseIterable {
    case today = "今天", week = "本周", month = "本月", year = "今年"
    var component: Calendar.Component { switch self { case .today: return .day; case .week: return .weekOfYear; case .month: return .month; case .year: return .year } }
}

private struct ArtistSummary: Identifiable {
    var name: String
    var seconds: Double
    var track: Track
    var id: String { name }
}

struct StatsView: View {
    var settingsAction: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var period = ListeningPeriod.month
    private var sessions: [ListeningSession] {
        guard let interval = Calendar.current.dateInterval(of: period.component, for: Date()) else { return [] }
        return library.snapshot.sessions.filter { interval.contains($0.date) }
    }
    private var total: Double { sessions.reduce(0) { $0 + $1.seconds } }
    private var rankedTracks: [Track] {
        let totals = Dictionary(grouping: sessions, by: \.trackID).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        return library.tracks.filter { totals[$0.id] != nil }.sorted { totals[$0.id, default: 0] > totals[$1.id, default: 0] }
    }
    private var rankedArtists: [ArtistSummary] {
        let groups = Dictionary(grouping: rankedTracks, by: \.artist)
        return groups.compactMap { name, tracks -> ArtistSummary? in
            guard let track = tracks.first else { return nil }
            let ids = Set(tracks.map(\.id))
            return ArtistSummary(name: name, seconds: sessions.filter { ids.contains($0.trackID) }.reduce(0) { $0 + $1.seconds }, track: track)
        }.sorted { $0.seconds > $1.seconds }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Picker("统计时间", selection: $period) { ForEach(ListeningPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int(total / 60))").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("分钟 · \(period.rawValue)").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text("聆听了 \(Set(sessions.map(\.trackID)).count) 首歌曲").font(.body).foregroundStyle(.secondary)
                }
                if rankedTracks.isEmpty {
                    MusicEmptyState(title: "每一次聆听，都算数", message: "播放音乐后，这里会记录你的聆听时长和喜爱的音乐。", symbol: "chart.xyaxis.line").frame(minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("艺人").font(.title2.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(Array(rankedArtists.prefix(10))) { artist in
                                    NavigationLink { SongsView(title: artist.name, ids: library.tracks.filter { $0.artist == artist.name }.map(\.id)) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ArtworkView(track: artist.track).frame(width: 136, height: 136)
                                            Text(artist.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                                            Text("\(Int(artist.seconds / 60)) 分钟").font(.subheadline).foregroundStyle(.secondary)
                                        }.frame(width: 136, alignment: .leading)
                                    }.buttonStyle(PressStyle())
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("常听专辑").font(.title2.bold())
                        AlbumGrid(albums: uniqueAlbums)
                    }
                    NavigationLink { SongsView(title: "常听歌曲", ids: rankedTracks.map(\.id)) } label: { Label("查看常听歌曲", systemImage: "music.note.list").font(.headline) }
                }
            }.padding(20)
        }.navigationTitle("统计").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("设置", systemImage: "gearshape", action: settingsAction) } }
    }
    private var uniqueAlbums: [[Track]] {
        var seen: Set<String> = []
        return rankedTracks.filter { seen.insert($0.albumKey).inserted }.prefix(8).compactMap { track in library.albums.first { $0.first?.albumKey == track.albumKey } }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("animatedBackground") private var animatedBackground = true
    @AppStorage("lyricBlur") private var lyricBlur = true
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("显示模式", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Toggle("播放背景动画", isOn: $animatedBackground)
                    Toggle("非当前歌词模糊", isOn: $lyricBlur)
                } header: { Text("外观") } footer: { Text("开启系统“减弱动态效果”后，会自动减少背景运动和转场。") }
                Section("资料库") {
                    LabeledContent("歌曲", value: "\(library.tracks.count)")
                    LabeledContent("专辑", value: "\(library.albums.count)")
                    LabeledContent("歌单", value: "\(library.playlists.count)")
                    Text("音频会复制到应用内保存，不会修改导入的原始文件。可通过系统“文件”App 访问 Flamingo 文件夹。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于 Flamingo") {
                    LabeledContent("版本", value: "1.0.0 · iOS 原生重建")
                    Text("参考 Flamingo 的经典音乐界面与交互思路，以 SwiftUI、UIKit 和 AVFoundation 原生实现。本地播放，无账号、无广告、无分析 SDK。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Link("原项目与源代码", destination: URL(string: "https://github.com/shouryadixitisverycool/Flamingo")!)
                    NavigationLink("开源许可") { LicenseView() }
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct LicenseView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "GNU General Public License v3.0. 完整许可见源码根目录 LICENSE。" }
        return text
    }
    var body: some View {
        ScrollView { Text(license).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding(20) }
            .navigationTitle("GPL-3.0").navigationBarTitleDisplayMode(.inline)
    }
}
