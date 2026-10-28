# 交互式滑块与轻量触觉反馈

## 审查与方案

原播放进度条位于 NowPlayingView.swift，使用 SwiftUI DragGesture 和单个 touching 布尔值。已有拖动预览与松手 seek，但缺少明确的取消、多触摸、后台和收起清理，轨道 6→9pt 使用普通 easeOut。原音量条位于 Design.swift，使用 MPVolumeView 的公开图片 API，但只有固定 6pt 样式。原触觉调用仅为播放器 panel 变化时的 sensoryFeedback。

本轮保留 PlayerStore 的 AVPlayer、seek token、pendingSeek 保护及实际位置校正。采用 UIViewRepresentable 包装 UIKit 控件，使用真实触摸生命周期驱动轨道外观；触觉只由明确的用户事件触发，不由播放观察、数值变化或动画帧推断。

## 进度条

AdaptiveSliders.swift 中的 AdaptiveScrubberControl 使用 UIControl 的 beginTracking、continueTracking、endTracking 和 cancelTracking。统一阶段为 idle、pressed、dragging、settling、cancelled。

轨道静止为 6.5pt，激活时通过 UIViewPropertyAnimator 将纵向比例扩展至 1.7，即约 11pt。进度背景与填充均使用 continuous 连续曲率圆角，音量轨道以相同曲率绘制并保留端帽。填充与背景位于同一个轨道容器，宽度不缩放。44pt 外部触摸区域和标签布局保持不变；活动轨道不显示独立大滑块。弹簧参数为 0.22 秒、阻尼 0.94，Reduce Motion 改为短 easeOut。动画可从当前呈现值接续，generation 排除过期完成回调。

拖动只更新局部预览和时间标签，不提交 seek；释放仅提交一次。音频时间继续正常推进，预览期间不会覆盖手指位置。松手后 PlayerStore 立即保留请求位置，seek 完成后再用实际位置校正。没有新增定时延迟或每帧 seek。

拖出控件时继续追踪同一手指并将值限制在两端；额外触摸不能替换本次交互。真正取消、后台、视图移除、切歌以及播放器不再处于 expanded 状态时清理轨道和预览。取消不提交 seek，旧手指释放也不会提交到新歌曲。VoiceOver 保留可调整语义，每次增减十秒，尊重有效时长和控件禁用状态。

## 系统音量

AdaptiveSystemVolumeSlider 继续显示真实的 MPVolumeView。轨道与透明 thumb 只通过公开的 setMinimumVolumeSliderImage、setMaximumVolumeSliderImage、setVolumeThumbImage 设置。没有查找内部 UISlider、遍历系统子视图、KVC、私有 API 或伪造的音量数值。

容器上的被动 UIGestureRecognizer 不取消 native touches、不延迟触摸，也不阻止或被其他 recognizer 阻止；它只观察开始、移动、结束和取消，用相同的纵向变换参数驱动 MPVolumeView。音量值、硬件按键、蓝牙和 AirPlay 仍由系统处理。不增加音量刻度或自定义音量震动。

公开 API 没有提供独立的“音量轨道动画进度”，因此变形作用于公开的整个 MPVolumeView，保持固定外部布局和水平方向尺寸。它不是对 Apple Music 内部实现的复刻；不同系统版本的 thumb、路由可用性及触摸手感需真机检查。原生控件能否调节当前输出设备由 iOS 决定。

## 触觉策略

InteractionFeedback.swift 中 PlayerHaptics 复用一个 soft UIImpactFeedbackGenerator 和一个 UISelectionFeedbackGenerator。只查询 Core Haptics 硬件能力，没有创建 CHHapticEngine。

| 事件 | 反馈 |
| --- | --- |
| 首次按住有效进度条 | intensity 0.35 的 soft impact，一次 |
| 到达进度开头或结尾 | 轻量 selection，离开边界超过 2% 才解除重复抑制 |
| VoiceOver 调整进度 | 一次 selection |
| 手动成功切换上一首/下一首 | 一次 selection，MiniPlayer 和全屏一致 |
| 全屏收藏、随机和循环操作 | 一次 selection |
| 连续拖动、播放时间更新、音量连续变化 | 不增加自定义触觉 |
| 播放/暂停、展开/收起、普通面板切换 | 本轮不增加触觉，以视觉反馈为主 |
| seek 完成、后台、自动切歌或远程命令 | 不增加触觉，避免异步或重复反馈 |

全部自定义反馈共享 120ms 限频，激活和边界发生在同一时刻时避免双重反馈。到达边界后停留或轻微抖动不会反复请求触觉。生成器只在需要时创建并复用；进度条启用时预热 impact，激活后预热可能的 selection，不逐帧 prepare。预热不是保证即时响应，系统会自行回收准备状态。

设置“播放 → 触觉反馈”默认开启，只控制应用提供的自定义反馈。关闭或进入后台释放生成器。硬件不支持或应用不在前台时不请求反馈；系统触觉设置、低电量及平台策略交由 UIKit 执行。应用没有使用非公开方式读取或覆盖系统触觉偏好，也不改变原生系统控件的反馈策略。

## 文件

- Flamingo/AdaptiveSliders.swift：两条自适应滑块、UIKit 触摸生命周期、取消与动画。
- Flamingo/InteractionFeedback.swift：反馈复用、硬件与前台门控、限频及边界滞回。
- Flamingo/NowPlayingView.swift：替换进度/音量组件，清理预览生命周期，接入部分离散操作反馈。
- Flamingo/RootView.swift：MiniPlayer 手动切歌反馈。
- Flamingo/Design.swift：移除旧固定样式音量桥接。
- Flamingo/Preferences.swift、StatsSettings.swift、FlamingoApp.swift：应用开关、默认值和后台资源清理。
- FlamingoTests/SliderInteractionTests.swift：预览与提交隔离、取消、旧释放、边界、快速重复触摸及限频用例。
- FlamingoUITests/FlamingoUITests.swift：拖动 seek 和重新展开后再操作用例。

## 验证边界

Windows 静态检查、Xcode 16.4 设备归档以及 56 项 Core/原生/UI 测试均通过，详见 VALIDATION.zh-CN.md 与构建 https://github.com/xu-68/music-player/actions/runs/40706373884 。其中滑块生命周期单元测试 5 项通过，进度拖动与重新展开的 UI 回归通过。未进行真实设备触觉、硬件同步或帧率验收，不能把模拟器结果描述为实际震感已经验证。

在 macOS 执行 `bash ios/scripts/build.sh test`，随后在真实 iPhone 检查：快速反复按住与松开、拖出区域、两个手指、两端抖动、暂停与播放时 seek、切歌/收起/后台取消、Reduce Motion、VoiceOver、硬件音量键、蓝牙/AirPlay，以及系统触觉和应用触觉分别关闭的组合。实际触觉强度、被动观察器与原生音量控件的兼容性必须实机确认。

## 官方依据

- [MPVolumeView 的公开外观 API](https://developer.apple.com/documentation/mediaplayer/mpvolumeview)
- [UIFeedbackGenerator.prepare](https://developer.apple.com/documentation/uikit/uifeedbackgenerator/prepare())
- [Apple 触觉设计指南](https://developer.apple.com/design/human-interface-guidelines/playing-haptics)

最终真机交付：IPA 提交 `73a74c55201173702a78e0ded644f8c586807e3e`，设备归档与包校验通过；最终封面微调版模拟器回归仍在 https://github.com/xu-68/music-player/actions/runs/40710233062 运行。按用户要求先交付真机测试，不等待该任务。此前 56 项通过对应 cc13c27，详见 VALIDATION.zh-CN.md。
