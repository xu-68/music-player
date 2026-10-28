import FlamingoCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var library
    @AppStorage("autoScanMusic") private var refresh = true
    @AppStorage("fadePlayback") private var fade = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("systemDecoderOnly") private var systemOnly = false
    @AppStorage("sleepFade") private var sleepFade = 5.0
    var body: some View {
        NavigationStack {
            Form {
                Section("资料库") {
                    LabeledContent("歌曲 / 专辑 / 歌单", value: "\(library.tracks.count) / \(library.albums.count) / \(library.playlists.count)")
                    Toggle("自动扫描媒体库", isOn: $refresh).accessibilityIdentifier("auto-scan-music")
                    Button("扫描媒体库", systemImage: "arrow.clockwise") { Task { await library.scanMusic() } }
                        .disabled(library.importing).accessibilityIdentifier("scan-music")
                }
                Section("播放") {
                    Toggle("播放 / 暂停淡入淡出", isOn: $fade)
                    Toggle("触觉反馈", isOn: $hapticFeedback).accessibilityIdentifier("haptic-feedback")
                    Toggle("仅使用系统解码器", isOn: $systemOnly)
                    Picker("睡眠定时淡出", selection: $sleepFade) { ForEach([0.0, 5, 10, 30], id: \.self) { Text("\(Int($0)) 秒").tag($0) } }
                    NavigationLink("睡眠定时") { SleepTimerView() }
                }
                Section("关于 music") {
                    LabeledContent("版本", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    Link("原项目与源代码", destination: URL(string: "https://github.com/shouryadixitisverycool/Flamingo")!)
                    NavigationLink("开源许可") { LicenseView() }
                }
            }.navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .onChange(of: hapticFeedback) { _, enabled in if !enabled { PlayerHaptics.shared.releaseResources() } }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
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
