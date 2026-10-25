# Flamingo · 原生 iOS 版

参考原 Flamingo 对 Apple Music 的交互还原思路，使用 SwiftUI、UIKit、AVFoundation 和 MediaPlayer 重新编写。运行时没有第三方依赖，不链接 Android、Compose、Flutter、React Native、FFmpeg AAR 或 WebView。最低 iOS 17，工程目标包含 iPhone 和 iPad。

**当前状态（2026-10-26）：已上传到用户指定的 `xu-68/music-player` 私有仓库，GitHub Actions / Xcode 16.4 的 10 项核心测试和 2 项模拟器界面/播放测试全部通过；iPhone ARM64 Release 归档成功，已生成并独立校验未签名 IPA，导出 7 张原生截图。真机及一比一视觉验收尚未完成。实际结果见 [验证记录](VALIDATION.zh-CN.md)。**

## 目录

```
ios/
  ASSESSMENT.zh-CN.md        迁移前评估、范围与限制
  DESIGN-NOTES.zh-CN.md      从原项目提炼的视觉和动画规则
  project.yml               XcodeGen 工程定义
  Flamingo/                 原生应用、播放器、导入和界面
  Packages/FlamingoCore/     无 UI 依赖的模型、队列、LRC/TTML 解析
  FlamingoUITests/           模拟器交互与截图测试
  scripts/build.sh           Mac 构建、测试、IPA 打包
  scripts/validate.py        Windows/macOS 静态检查
```

## 已实现的代码路径

- 从系统文件选择器批量导入音频，复制文件、读取标题/歌手/专辑/序号/封面，SHA-256 去重；不支持或损坏的文件单独报告，不中断其他导入。
- 首页横向精选和最近播放、资料库分类、专辑详情、歌手、歌曲搜索、收藏、创建/编辑/重排歌单和删除确认。
- AVPlayer 本地播放、进度拖动、上一首/下一首、随机队列、列表循环和单曲循环、睡眠定时。
- 音频会话、后台音频、锁屏元数据和远程播放控制、AirPlay 路由选择、真实系统音量、耳机拔出暂停和音频中断处理。
- 经典底部三个标签页、迷你播放器、共享封面展开、下拉关闭、暂停封面缩放与阴影、专辑封面驱动的缓慢背景运动。
- 导入外部 LRC/TTML，读取能通过 AVFoundation 暴露的嵌入歌词；时间偏移、重复时间戳翻译、增强 LRC 逐字时间、常见 TTML p/span 时间、自动跟随、点击跳转与逐字遮罩点亮。
- JSON 原子持久化、实际播放时间统计、独立的界面测试数据目录与偏好套件；正式启动不会填充测试音乐。
- 系统深浅色、VoiceOver 操作标签与进度调整、系统减弱动态效果适配；使用系统文本样式的列表支持动态字体。播放器与歌词仍需针对最大辅助字号继续实机验收。

代码存在不表示这些能力已经在设备上验证。特别是后台播放、中断、iCloud 文件导入、音频格式与性能，需要按下面的清单验证。

## 使用 GitHub Actions 构建（用户已选择）

仓库为 https://github.com/xu-68/music-player ，根目录已有 `.github/workflows/ios.yml`：

1. 打开仓库的 **Actions**。
2. 选择 **iOS Native Build** → **Run workflow**。
3. `build` 任务在 macOS 上运行 Core 单元测试，生成 Xcode 工程，归档并生成真实 iPhone ARM64 未签名 IPA，再验证 Mach-O 平台与包结构。
4. `ui-tests` 任务在设备包成功后独立运行模拟器界面/播放测试，导出原生截图。必须分别检查两个任务结果；设备编译通过不代表界面测试已通过。
5. 在构建页面的 Artifacts 下载 `Flamingo-unsigned-ipa`；截图保存在 `Flamingo-test-results` 的 `.xcresult` 附件中，可在 Mac 的 Xcode 打开。

工作流只使用读取仓库权限，不要求上传苹果证书。**未签名 IPA 仍需按你的安装方式签名，无法直接点开安装。** 若工作流失败，应先查看日志并修复，不能把本地语法检查当作远程构建成功。

仓库已由当前账号 `xu-68` 创建并完成推送。它是独立原生仓库，未上传 Android 参考工程、本地校验器依赖或任何认证信息。

## 在 Mac 本地编译

安装完整 Xcode 并完成首次启动，选择命令行工具。安装 XcodeGen 后，在仓库根目录运行：

```bash
brew install xcodegen
bash ios/scripts/build.sh simulator
bash ios/scripts/build.sh test
bash ios/scripts/build.sh unsigned
```

也可以执行 `cd ios && xcodegen generate`，再使用 Xcode 打开 `Flamingo.xcodeproj`。源代码以 `project.yml` 为工程真源，生成的 `.xcodeproj` 已加入忽略列表。

签名导出使用你自己在 Xcode 配好的团队、唯一 Bundle ID 和导出配置：

```bash
export TEAM_ID="YOUR_APPLE_TEAM_ID"
export BUNDLE_ID="your.own.flamingo"
export EXPORT_OPTIONS_PLIST="/absolute/path/to/ExportOptions.plist"
bash ios/scripts/build.sh signed
```

导出配置由所选安装/分发方式决定，使用 Xcode 导出时生成的配置最稳妥。构建脚本不会代为创建开发者账号或证书。

## 自动测试与实际验收

Core 的 10 项测试覆盖：LRC 时间精度/偏移/翻译、多时间戳、逐字时间、TTML 实体/翻译/相对时间/无效 XML、队列循环、随机队列保序与恢复、重复歌曲、删除当前歌曲并保留队列、随机启动完整性、资料库序列化和时间格式。

UI 测试通过显式 `--ui-testing` 参数生成原创低音量测试音频和程序绘制封面，使用 `Documents/FlamingoUITests` 及单独 UserDefaults 套件；依次保存首页、资料库、全屏播放器、歌词、队列和统计截图，验证播放/暂停及歌词跳转。它不以仿造网页代替原生运行。

本地静态检查：

```bash
python -m pip install --target ios/.validation-tools tree-sitter tree-sitter-swift PyYAML
python ios/scripts/validate.py
```

这个脚本只验证 Swift 语法树、资源格式和工程路径，**不会执行 Swift 类型检查、单元测试或模拟器测试**。

必须完成的设备验收：

- 使用自己的 MP3、AAC/M4A、ALAC、FLAC、WAV 测试导入、播放和标签；实际格式支持取决于系统，不把所有 M4A 误标为无损。
- 测试 iCloud 尚未下载的文件、多选导入、重复导入、应用重启、删除正在播放歌曲和歌单编辑。
- 锁屏/切后台连续播放，蓝牙/AirPlay 切换、耳机拔出、来电中断及恢复、系统音量和定时停止。
- 同一首歌及同一封面对照原 Flamingo/经典 Apple Music，比较截图和展开/收起/拖动/暂停/歌词视频，调整弹簧、封面尺寸和间距。
- 在小屏 iPhone、横屏、iPad、深浅色、VoiceOver、减弱动态效果和大字体环境验证布局。
- 使用 Instruments 测试掉帧、能耗、导入内存和大型资料库性能；当前没有测得帧率、包体或功耗数字。

## 明确限制

当前没有移植 Android Xposed/状态栏插件、AAR 解码器、桌面小组件、视频动态封面、交叉淡化和完整 TTML 规范。TTML 已覆盖常见时标与逐字 span，但复杂和声、逐词独立翻译、布局区域、字体样式、帧率倍数和 seq 时间容器仍需扩展验证。JSON 适合首轮本地库实现，超大型库的索引和检索需在数据量实测后评估。

视觉还原是本次实现的目标，尚不能宣称“1:1”“120 FPS”或“完全等同系统 Music”。原生技术栈减少跨平台桥接，并不自动证明流畅。

保留上游 GPL-3.0 许可和来源。Android 工程留作参照，不参与 iOS 构建或 IPA 打包。
