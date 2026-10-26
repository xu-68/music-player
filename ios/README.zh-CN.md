# Flamingo 原生 iOS

以 Flamingo v2.1.0（上游提交 `290a792`）为参照，以 SwiftUI、UIKit、AVFoundation、MediaPlayer 重写，支持 iOS 17 以上的 iPhone 和 iPad。Android、Compose、ExoPlayer、MMKV 和 AAR 不参与构建。FFmpeg 7.1.5 作为本地音频解码依赖，从官方源码构建静态库；界面仍全部为原生视图。

## 音乐文件管理（当前版本）

音乐仅通过应用自带的 Music 文件夹管理。首次启动后，在 Apple“文件”App 中打开“浏览 → 我的 iPhone（或 iPad）→ Flamingo → Music”，将音乐移动或复制到这里，允许子文件夹。回到应用后点击首页、资料库或设置中的“扫描媒体库”。设置中的“自动扫描媒体库”默认开启，在启动和返回前台时更新；它不是后台持续监视。

扫描直接索引并播放 Music 内的原文件，不再弹出音乐文件选择器、不再授权其他文件夹、不再复制一份音频。短音频同样纳入扫描，单个损坏文件会显示具体失败原因。歌词可与音频同名放在相同目录，本地动态封面仍支持 anim/专辑名.mp4。

在歌曲列表滑动删除并确认“删除歌曲及音乐文件”，会删除 Music 内对应的源文件并同步清理歌单和队列。源文件删除失败时保留歌曲并显示错误。在“文件”App 中移走或删除文件后，下次扫描移除失效条目。播放统计保留。旧版已导入的音频会迁移到 Music，保留歌曲标识、收藏及歌单；外部文件夹不再扫描。

## 功能

- 原版经典三标签布局、推荐卡片与最近播放；连续四首以上同专辑的历史合并为专辑卡片。
- 应用自带 Music 文件夹、递归扫描、前台自动扫描与手动扫描；直接索引原文件、保留子文件夹和文件名、同步删除；同名歌词和 `anim/专辑名.mp4` 匹配。
- 歌曲、专辑和艺人搜索；标题、时长、艺人、修改日期排序；艺人拆分与关注；艺人专辑、单曲/EP 和参与发行分类。
- 歌单名称、描述、照片封面与 0–4 张独立封面拼图；允许重复歌曲、逐项删除、多选移除、拖动排序、模糊搜索、置顶及置顶顺序、批量加入其他歌单、删除撤销。
- AVPlayer 播放与系统解码；自动模式下，系统无法读取的音频通过 FFmpeg 解码为本地 Float32 PCM/CAF，再由原生播放器播放。保留原文件用于分享。转换缓存会增加磁盘占用，并非把解码后的音频内置到 IPA。
- 队列添加、下一首/最后播放、调整顺序、滑动移除/移至下一首、清空待播、随机及三种循环；恢复完整队列和播放进度，重启不自动发声。
- 200ms 播放/暂停淡入淡出；倒计时、本首结束和队列结束三种睡眠模式，可延长/取消，支持 0/5/10/30 秒淡出。
- 内嵌歌词与同名 LRC/TTML/XML；TTML 优先且损坏时回退 LRC；多时间戳、逐字、重复时间戳翻译、Apple TTML 翻译/音译、重叠行共同聚焦、v2 对唱靠右、间奏提示、字体权重、平衡换行、模糊、点击跳转与跟随。
- 本地静音循环视频封面及专辑黑名单。**按用户明确选择，不接入在线封面服务，不上传歌曲元数据。**
- 最近 50 首与历史开关；日/周/月/年/全部统计、跨日时长、播放过半计数、歌曲/艺人/专辑排行；移除音频后保留统计标签；原版统计 JSON 导入、合并去重、覆盖、导出和清空确认。
- 迷你播放器共享封面转场、下拉关闭、暂停缩放、封面背景动画；音量条、深浅色、栏模糊、圆角和减弱动态效果设置。
- 后台音频、锁屏信息与远程控制、耳机断开/音频中断处理、系统音量、AirPlay、文件分享和通过“文件”App 管理 Music 文件夹。

逐项依据与验证记录见 [PARITY.md](PARITY.md) 和 [VALIDATION.zh-CN.md](VALIDATION.zh-CN.md)。存在代码不等于硬件和视觉效果已经验收；不能把模拟器测试说成实机测得 120 FPS 或像素、运动曲线完全相同。

## 构建

仓库：[xu-68/music-player](https://github.com/xu-68/music-player)。Actions 的 **iOS Native Build** 自动执行：

1. 编译并缓存 FFmpeg 的 iPhone ARM64 与模拟器 ARM64 静态 XCFramework。
2. 运行 FlamingoCore 测试，归档 Release 应用，校验 IPA 内的 ARM64 Mach-O 与 iOS 平台标记。
3. 独立运行 iOS 原生单元测试、真实播放与 UI 交互测试，导出截图和 xcresult。
4. 上传 `Flamingo-unsigned-ipa` 与 `Flamingo-test-results`。两个任务均通过后才能接受该轮自动回归。

仓库已按用户要求公开，保留 GPL-3.0 许可。Windows 用户无需本地 Mac：在仓库 Actions 中选择 **iOS Native Build → Run workflow → main**，等待 `build` 和 `ui-tests` 均通过后，从该次运行的 Artifacts 下载 `Flamingo-unsigned-ipa`。解压得到 `.ipa`；它仍需要签名才能安装。测试截图与完整结果位于同次运行的 `Flamingo-test-results`。请以验证记录中的通过提交为准，不要把仅编译成功、测试失败的产物当作验收版本。

在 Mac 本地执行：

```bash
brew install xcodegen ffmpeg
bash ios/scripts/generate_audio_fixtures.sh
bash ios/scripts/build.sh test
bash ios/scripts/build.sh unsigned
```

第一次构建需要下载并编译 FFmpeg。`build_decoder.sh` 固定源码版本和 SHA-256；`ffmpeg` 命令行程序只用于生成合成测试音频，不打包进应用。XcodeGen 的 `ios/project.yml` 是工程定义的真源；先运行 `build_decoder.sh` 再生成工程，或直接使用上面的构建脚本。

签名构建支持 `TEAM_ID`、`BUNDLE_ID`、`EXPORT_OPTIONS_PLIST` 三个环境变量，然后执行 `bash ios/scripts/build.sh signed`。证书与描述文件不写入仓库。**未签名 IPA 需要签名后安装；它不是直接可安装的 App Store 包。**

Windows 的 `scripts/validate.py` 仅验证语法树、工程路径、资源和 plist，不能替代 Xcode 类型检查与运行测试。

## 平台与验收边界

- iOS 仅扫描应用 Documents/Music，不扫描设备其他位置。音频由用户移入 Music，扫描不复制音频；应用内删除会删除 Music 中的原文件。
- Xposed/LSPosed 状态栏插件、Android 通知图标和 AudioTrack/MediaCodec 专属参数不适用于 iOS，对应系统播放能力使用锁屏、原生音频会话与路由。
- 源码中未发现真实 Android AppWidgetProvider；`ui/widgets` 是应用内 Compose 控件。没有据此额外加入 WidgetKit 或 App Group 依赖。
- 逐项功能回归、静态截图检查、实机后台/蓝牙/AirPlay 和动画视频/性能验收是不同证据。尚无真机权限和性能记录时，不能宣称全部实机验收完成。
- TTML 兼容目标是原项目声明支持的格式，不宣称完整实现所有 W3C TTML 布局区域、样式与时间容器规范。

正式启动使用用户资料库。UI 测试只有传入 `--ui-testing` 才会生成原创合成音频与绘制封面，数据目录、偏好套件独立；这些演示素材不进入 Release。

GPL-3.0。原项目的许可保留；FFmpeg 未启用 GPL/非自由组件，其 LGPL 源码与完整构建步骤可通过仓库固定版本脚本重现。
