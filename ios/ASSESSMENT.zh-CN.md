# Flamingo iOS 重建评估

日期：2026-10-22。参照版本：`v2.1.0`，提交 `290a79213da1f6bf61803bb6b822d444e0dc74d2`。

## 结论与已确认方向

用户已选择原 Flamingo 对应的经典 Apple Music 风格。采用 SwiftUI + UIKit + AVFoundation 原生重写，最低 iOS 17，支持 iPhone 和 iPad。视觉参照是仓库 `docs/pics/1.png` 至 `6.jpg`，以及原 NowPlaying、YosLyricView、Library、Stats 实现。原 Android 工程保留。

原工程使用 Kotlin 2.0、Jetpack Compose、Android Gradle Plugin、Media3/ExoPlayer、MediaStore、MMKV 和多项 AAR。应用源码目录有 107 个文件，其中 47 个文件直接导入 android 或 Media3；该计数不包含间接依赖，不能据此推断可复用比例。没有 iOS target 或 Xcode 工程。Compose Multiplatform 可以复用部分 UI，但仍需拆分 Android API、替换资源与多项依赖，并另写 iOS 播放层。针对苹果端体验优先的目标，原生重写更直接。

## 实施边界

| 能力 | iOS 实现 |
| --- | --- |
| 首页、资料库、统计 | 原生大标题、系统字体、SF Symbols、粉红色强调、封面网格 |
| 播放器 | 迷你播放器到全屏的共享封面转场、拖动关闭、暂停缩放、专辑色彩流动背景 |
| 播放 | AVPlayer、本地文件、队列、上一首/下一首、随机和循环、拖动进度 |
| 系统集成 | AVAudioSession、MPNowPlayingInfoCenter、MPRemoteCommandCenter、AirPlay、系统音量 |
| 导入和存储 | 文件选择器，复制到应用 Documents，异步解析标签/封面，JSON 原子持久化 |
| 歌词 | LRC、增强 LRC、TTML 时间轴与 span 逐字时间，翻译、自动滚动、点击定位 |
| 歌单/收藏/统计 | 本地持久化、编辑歌单、实际播放时间统计、最近播放 |
| 设备适配 | 深浅色、动态字体、减弱动态效果、VoiceOver、窄屏/横屏与 iPad 自适应 |
| 构建 | XcodeGen 工程定义、Mac 构建脚本、macOS CI、未签名 IPA 与签名导出路径 |

Android 的 Xposed、状态栏歌词广播、通知渠道和 AAR 插件不移植；iOS 通过锁屏媒体控件实现对应系统能力。FFmpeg AAR 无法用于 iOS，首版使用 AVFoundation 支持的格式，对不支持/损坏文件报告错误。完整 TTML 排版、复杂背景和声、视频动态封面、桌面小组件与原 Android 特有设置不应被宣称已完全等价。

## 视觉验收目标

经典布局：大标题约 34pt、普通列表 17pt、22pt 分区标题、系统字体和 SF Symbols；底部保留经典三个标签页与上方迷你播放器。首页使用横向推荐封面、最近播放；资料库使用歌单/歌手/专辑/歌曲入口。全屏播放器使用封面主色、连续圆角封面、独立的进度和音量控制、底部歌词/AirPlay/队列。避免依靠 iOS 新版本默认 TabView 样式以免自动变为 Liquid Glass。

动态目标：展开/关闭采用可打断弹簧，封面共享几何，向下拖动跟手并依据距离/预测距离关闭；暂停时封面收缩；歌词根据真实播放时间逐行/逐字点亮，可手动浏览并恢复跟随；系统减弱动态效果开启后减少背景运动和转场。

“几乎一比一”是验收目标，不能仅凭写完源码视为达成。必须使用同一封面与歌曲、相近设备尺寸，在 iPhone 截图及视频上比较间距、颜色、时间曲线与交互。仓库图片是静态参照，不能据此准确还原全部动画参数。

## 当前构建条件与验证规则

当前宿主为 Windows，未发现 Swift 编译器、Xcode 或 iOS SDK。因此本地不能执行 iOS 编译、模拟器测试、音频路由测试、性能检测或签名。静态检查结果与 macOS 上待执行的测试分开记录。未签名 IPA 不是直接可安装包，必须通过合适签名/侧载流程安装。开发者证书与描述文件不存入源码。

该本地目录是上游完整 Git 克隆；尚未创建用户账号下的远程 Fork，也未触发云端构建。原仓库为 GPL-3.0，保留 LICENSE 和来源记录。

## 参考

- 原项目：https://github.com/shouryadixitisverycool/Flamingo/tree/v2.1.0
- Compose 与 Jetpack Compose：https://kotlinlang.org/docs/multiplatform/compose-multiplatform-and-jetpack-compose.html
- AVPlayer：https://developer.apple.com/documentation/avfoundation/avplayer
- 锁屏控制：https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter
- 构建与分发：https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution
