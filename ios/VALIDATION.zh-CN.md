# 验证记录

## 当前状态：2026-10-26 续作

主要功能代码已实现，尚未完成最新版本的完整回归和真机验收。以下最新状态优先于后面的首版历史记录。

### 上轮实际结果

- 提交 `d2524f19364669c7ecc8a5d90c75b2ef30ef502a`，北京时间 04:58 提交，05:07 完成。
- 构建：https://github.com/xu-68/music-player/actions/runs/40233228825 。
- Core 测试、ARM64 Release 归档、IPA 校验及上传通过。
- 原生播放测试 4/4 通过；音频测试 5 项中 1 项出现 4 个标签断言失败；UI 测试 6 项中 3 项失败。
- 音频失败涉及 FLAC 专辑、专辑艺人、作曲及日期；UI 失败涉及截图辅助函数错误要求被全屏播放器遮挡的迷你播放器可点击，以及睡眠剩余时间读取字段错误。
- 下载的睡眠失败现场无障碍树显示 `sleep-remaining` 的 label 为 `34:57`、`34:56`，说明延长操作已经生效。

### 本轮修复及阻塞

- 修复提交 `b1c50d5c0cd8cf87a1cf312001b6aec523593f56`：为系统可播放文件新增 FFmpeg 标签/封面探测，不生成 PCM 音频；修正上述 UI 断言。
- 后续补充探测回归：FLAC/WMA/OGG/Opus/WavPack 标签、无转码副产物、损坏文件失败；FLAC 导入继续断言使用原文件播放。
- Windows 本地检查通过：25 个 Swift 文件语法树、工程配置、资源、plist，以及 `git diff --check`。本地没有 Swift/Xcode 编译器；此结果不等于类型检查或运行通过。
- 新构建 https://github.com/xu-68/music-player/actions/runs/40265462161 **没有启动 runner**。GitHub 明确提示账户付款失败或消费上限不足，UI 任务跳过，没有新 IPA。
- 需在 GitHub Settings → Billing & plans 恢复 Actions 额度，或使用可用 Mac。恢复后对最新 main 手动执行 iOS Native Build；不要只重跑较早提交来代替最终版本验收。

### 恢复后的完成顺序

1. 执行最新 main 的 Core、音频/播放、UI 测试与 ARM64 归档，修复实际出现的失败，直到两项任务全部通过。
2. 下载并校验该提交的 IPA，检查新截图，再更新本文件中的实际结果、产物链接和 SHA-256。
3. 签名后进行真机后台、锁屏、蓝牙、AirPlay、文件导入，以及 iPad、大字号、动画和性能验收。

根目录的 `Flamingo-iOS-unsigned.ipa` 仍是首版旧包，不能作为本轮修复版本交付。源码 ZIP 可由 `scripts/package_source.py` 更新，但不代表已通过 Xcode 构建。

## 首版历史记录（不代表当前版本通过）

日期：2026-10-26（Asia/Shanghai）。仓库：https://github.com/xu-68/music-player 。

代码提交：`9531386904bfeac8b5218da3fcb076e16f56fcf8`。构建：https://github.com/xu-68/music-player/actions/runs/40224260658 。macOS-15 / Xcode 16.4。

| 检查 | 结果 |
| --- | --- |
| 14 个 Swift 文件的 Tree-sitter 语法解析 | 通过；不等于 Swift 类型检查 |
| Swift 源码行尾空白检查 | 通过 |
| XcodeGen 源码/Package 路径、YAML 格式 | 通过；已在 macOS 运行 XcodeGen 并成功生成工程 |
| Info.plist 与工程配置一致性 | 通过 |
| 隐私清单、资产 JSON、PNG 签名 | 通过 |
| 内置许可与上游 LICENSE 一致性 | 通过 |
| 原生源码包排除 Android 工程和本地验证工具 | 已生成独立源码 ZIP |
| 10 项 Swift Core 测试 | macOS 执行通过，0 失败 |
| 2 项原生 UI/播放交互与截图测试 | 模拟器执行通过，0 失败；涵盖六个主要界面、播放/暂停、歌词跳转与恢复播放 |
| 原生截图 | iPhone 16 Pro 模拟器导出 7 张截图，已查看首页、资料库、播放器、歌词、队列和统计；使用明确隔离的原创测试音频/封面，保存在 docs/screenshots |
| iOS 编译 / archive / IPA | ARM64 设备 Release 归档成功，IPA 上传成功 |
| IPA 独立检查 | 云端与下载后本地均通过 ZIP / Mach-O / ARM64 / iOS 平台 / Info.plist 校验 |
| GitHub 仓库 / 推送 / Actions 运行 | 已创建 xu-68/music-player 私有仓库，上传独立原生源码并触发构建 |
| 真机后台、锁屏、蓝牙、AirPlay、导入 | 未验证 |
| 与原 Flamingo / Apple Music 的截图与视频对照 | 未验证 |
| 帧率、包体大小、内存、能耗 | 未测量 |

设备 IPA：441,399 字节，最低 iOS 17.0，Bundle ID `org.flamingo.local.player`，**未签名**。

SHA-256：`e04228be514c83245fa332dcf959327904dea79ef27522380c97cd36201e90c5`。

产物：https://github.com/xu-68/music-player/actions/runs/40224260658/artifacts/12610815631 。

首轮模拟器运行证明原生应用可以编译、安装并启动；界面播放测试发现 `.isModal` 标记错误传播，使进度条被识别为警告弹窗并干扰交互。已经移除该错误标记，保留根视图的背景无障碍隐藏；修复后两项测试全部通过，耗时约 115 秒。界面测试专用背景动画关闭以避免连续动画影响自动化等待；生产环境默认仍启用背景动画。

原生测试结果与截图：https://github.com/xu-68/music-player/actions/runs/40224260658/artifacts/12610692527 。

设备编译与模拟器测试分为两个任务。测试失败不会被写成成功；原生交互、实际掉帧和真机音频路由仍需分别验证。未签名 IPA 必须签名后才能安装。
