# Flamingo 原生 iOS

以 Flamingo v2.1.0（上游提交 `290a792`）为参照，以 SwiftUI、UIKit、AVFoundation、MediaPlayer 重写，支持 iOS 17 以上的 iPhone 和 iPad。Android、Compose、ExoPlayer、MMKV 和 AAR 不参与构建。FFmpeg 7.1.5 作为本地音频解码依赖，从官方源码构建静态库；界面仍全部为原生视图。

## 音乐文件管理（当前版本）

音乐仅通过应用自带的 Music 文件夹管理。首次启动后，在 Apple“文件”App 中打开“浏览 → 我的 iPhone（或 iPad）→ Flamingo → Music”，将音乐移动或复制到这里，允许子文件夹。回到应用后点击设置中的“扫描媒体库”。设置中的“自动扫描媒体库”默认开启，在启动和返回前台时更新；它不是后台持续监视。

扫描直接索引并播放 Music 内的原文件，不再弹出音乐文件选择器、不再授权其他文件夹、不再复制一份音频。短音频同样纳入扫描，单个损坏文件会显示具体失败原因。歌词可与音频同名放在相同目录。

在歌曲列表滑动删除并确认“删除歌曲及音乐文件”，会删除 Music 内对应的源文件并同步清理歌单和队列。源文件删除失败时保留歌曲并显示错误。在“文件”App 中移走或删除文件后，下次扫描移除失效条目。旧版已导入的音频会迁移到 Music，保留歌曲标识、收藏及歌单；外部文件夹不再扫描。

## 历史与统计移除

已移除“历史与备份”设置板块、统计页面、播放次数/时长采集、统计 JSON 导入导出及首页最近播放。旧资料库仍能读取歌曲、收藏和歌单，旧历史字段会被忽略并在保存时移除。播放队列和进度恢复保留。

## 本轮界面优化

删除整个外观设置板块：应用跟随系统，音量条和封面取色背景动画固定启用，收起圆角由 mini player 实测高度自动计算。共享转场覆盖容器、封面、歌曲标题和艺人；下拉直接更新同一进度，释放时以预测落点选择状态，并将手势速度归一化后传入质量/刚度/阻尼弹簧。新增 30% 拖动、反向接管与无效输入测试用例；仅静态校验，原生执行留待统一构建。

播放详情竖屏按用户提供的 Apple Music 截图测量相对位置：顶部拖动条 7.3%、信息行中心 13.75%、进度轨道 66.2%、播放控制 76.9%、音量条 87.4%、底部按钮 93.1%。未来歌词随播放接近渐清晰；手动浏览时关闭模糊。进度与音量轨道采用 6.5pt 连续曲率圆角，AirPlay 保留系统选路交互并以固定尺寸符号呈现。上述比例已落实到代码，尚未通过本轮原生截图核验，不代表已达像素一致。

移除平衡歌词换行、动态封面的设置、导入、扫描匹配和视频播放实现，旧资料库中的视频字段会被忽略。艺人拆分固定使用逗号，设置不再显示拆分符号及说明小字。手动扫描仅保留设置入口。已按用户指示进入 2.3.1（6）推送与设备 IPA 构建流程，构建及校验结果记录在本轮交付说明。

首页头像与大标题同排，图标 30pt、点击区域 44pt。底部 mini player 与双标签导航统一使用自适应超薄材质、方向性边缘高光与柔和投影；移除高亮整圈描边，选中色统一为音乐红。导航仅保留 Home / Library；搜索入口仅在歌曲页。开启系统“降低透明度”时使用实色背景。

Windows 结构校验通过不等于原生编译或真机视觉验收；本轮 Xcode 与截图检查结果以对应 Actions 为准。

## 功能

交互式进度条、原生音量条形变与轻量触觉策略见 [SLIDERS-HAPTICS.zh-CN.md](SLIDERS-HAPTICS.zh-CN.md)。设置“播放 → 触觉反馈”可以关闭应用自定义反馈；实际触觉与系统音量行为仍需真实 iPhone 验收。

- Home / Library 双标签布局与推荐卡片；不再记录或展示播放历史与统计。
- 应用自带 Music 文件夹、递归扫描、前台自动扫描与手动扫描；直接索引原文件、保留子文件夹和文件名、同步删除；同名歌词匹配。
- 仅歌曲页面保留搜索（匹配歌曲、专辑和艺人）；标题、时长、艺人、修改日期排序；艺人默认按逗号拆分与关注；艺人专辑、单曲/EP 和参与发行分类。
- 歌单名称、描述、照片封面与 0–4 张独立封面拼图；允许重复歌曲、逐项删除、多选移除、拖动排序、置顶及置顶顺序、批量加入其他歌单、删除撤销。
- AVPlayer 播放与系统解码；自动模式下，系统无法读取的音频通过 FFmpeg 解码为本地 Float32 PCM/CAF，再由原生播放器播放。保留原文件用于分享。转换缓存会增加磁盘占用，并非把解码后的音频内置到 IPA。
- 队列添加、下一首/最后播放、调整顺序、滑动移除/移至下一首、清空待播、随机及三种循环；恢复完整队列和播放进度，重启不自动发声。
- 200ms 播放/暂停淡入淡出；倒计时、本首结束和队列结束三种睡眠模式，可延长/取消，支持 0/5/10/30 秒淡出。
- 内嵌歌词与同名 LRC/TTML/XML；TTML 优先且损坏时回退 LRC；多时间戳、逐字、重复时间戳翻译、Apple TTML 翻译/音译、重叠行共同聚焦、v2 对唱靠右、间奏提示、系统 Bold 可缩放字体、点击跳转与跟随。
- 使用静态专辑封面；封面取色背景动画保留。
- 迷你播放器共享封面转场、下拉关闭、暂停缩放、封面背景动画；音量条固定显示、应用跟随系统、圆角自动衔接与系统减弱动态效果支持。
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

## 重签名后灵动岛不能返回应用的排查

系统 Now Playing 的点击返回由 iOS 负责，应用没有独立的“灵动岛点击”回调。若出现前台仍展示播放状态、后台点击无法回到应用，应先核对最终安装包的身份；这些现象本身不能证明根因。

在全能签中检查所选描述文件的 App ID。若它是明确的 `PREFIX.com.example.music`，签名时的 Bundle ID 应为 `com.example.music`；PREFIX 不属于 Bundle ID。不要直接照搬此示例，或随意改成其他已安装应用的标识。通配符描述文件需要签名工具正确展开最终 application-identifier，不能把星号写入最终签名身份。

签名后导出的 IPA 才是核查对象，未签名构建无法验证此项。在 Mac 解压签名后的 IPA，执行：

```bash
python3 ios/scripts/verify_signing.py /path/to/Payload/Flamingo.app
```

检查脚本验证签名、Bundle ID、签名 application-identifier 与描述文件授权的一致性，不输出证书或描述文件内容。通过后仍需在 iOS 18.7 真机验证：应用内播放、切到桌面点灵动岛返回、重新进入应用时灵动岛状态、锁屏及控制中心控制。若修改 Bundle ID，系统可能将其视为新应用；先备份原应用的音乐及资料库，不要先卸载旧应用。

依据：Apple TN3125 https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
