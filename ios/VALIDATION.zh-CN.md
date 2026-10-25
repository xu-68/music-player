# 验证记录

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
