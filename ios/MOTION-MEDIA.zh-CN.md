# 播放器交互动画与系统媒体集成

## 审查结果

项目最低版本为 iOS 17，使用 SwiftUI NavigationStack/TabView、单个顶层 PlayerStore 和 AVPlayer。解码、文件扫描、队列与歌词解析继续沿用既有实现。

原 RootView 通过 expanded 布尔值插入播放器，并采用底部 move 转场。namespace 参数没有真正连接共享元素。NowPlayingView 又单独维护拖动位移，造成手势状态与容器进出状态分离。下拉释放主要使用固定距离判断。展开与收起期间没有统一的中断管理。

原 PlayerStore 已有 playback 音频会话、Now Playing、Remote Command、音频中断及旧输出设备断开处理；SystemVolumeSlider 和 AirPlayButton 分别采用 MPVolumeView、AVRoutePickerView。需要补齐的是静态媒体信息缓存、受限频率的系统进度校正、媒体服务重置，以及用户在中断期间主动暂停后的恢复规则。

## 动画架构

PlayerMotion.swift 定义 presentation、returnToPlayer、control、artwork、panel 和 reduced 动画参数。PlayerPresentation 管理 collapsed、expanding、expanded、dragging、collapsing 五种状态，并用 generation 排除已被中断动画的过期完成回调。

RootView 保留主 Tab 和导航树，只在它们上方维护一个播放器容器。播放器在有当前歌曲时保持挂载，通过可动画 modifier 改变实际呈现矩形；内部仍按完整视口布局，避免随着容器缩放逐帧重新排整页内容。MiniPlayer、目标封面和容器矩形由 PreferenceKey/GeometryReader 在命名坐标系中测量。封面在独立共享层沿同一进度插值，保持原始宽高比例，并在歌词/队列页使用小封面目标。几何合并忽略空值，全屏稳定态保留封面兜底；不透明底层阻止模糊边缘透出主页面。

评估 matchedGeometryEffect 后采用显式矩形插值：这一实现需要明确取得正在呈现的弹簧进度，以便手势接管，并同时控制容器和独立封面。删除了原先没有实际用途的 namespace。没有引入 UIKit Presentation Controller 或私有 API。

PlayerContainerTransform 的 animatableData 记录渲染进度，记录字段不触发 Observation 更新。新拖动从该进度开始，以无动画 Transaction 直接追随手势。DragGesture 使用根视图坐标系，避免容器自身缩放改变手势坐标。归一化距离取实际容器顶部移动距离，释放通过 predictedEndTranslation 决定完成收起还是弹簧归位；反向拖动继续使用同一个拖动原点。

顶部拖动区使用高优先级拖动手势，封面区也可拖动；歌词、队列、音量条和进度条保持各自的滚动/拖动语义。MiniPlayer 展开按钮和播放控制是独立按钮。关闭按钮与 VoiceOver escape 均进入同一状态机。

控件按进度淡入；背景遮罩、底栏显隐、圆角和封面同步变化。旋转或进入后台时，尚在拖动的状态会归位，避免停在半展开状态。从播放器前往艺人/专辑时，等待容器收起完成后再导航。展开前通过公开 responder API 收起键盘，保留搜索内容。

Reduce Motion 使用透明度过渡，不执行容器位移和共享封面变形。

## 内部反馈和性能

播放/暂停采用 SF Symbols 的 contentTransition，启用 Reduce Motion 时降级。按钮使用一致的轻量按压反馈；本轮没有增加触感反馈功能。封面在暂停时克制缩小，恢复时回弹；图片切换淡入淡出，视频未准备好显示时保留底下的静态封面。视频桥接只在播放意图或 URL 变化时调用 play/pause，不随每帧布局重复调用。

MiniPlayer 进度和当前逐字歌词在独立 TimelineView 中读取媒体时钟。隐藏、暂停或进入后台时停用对应时间线；歌词布局加入 Layout cache，复用测量/放置结果。已有低频背景动画继续复用。Info.plist 与 XcodeGen 配置同时启用 CADisableMinimumFrameDurationOnPhone；前景动画不固定锁在 60Hz，实际刷新率由系统、设备状态和负载决定。

进度拖动期间显示本地 scrubbing 值，释放后提交 seek。PlayerStore 在 seek 完成前保留请求位置，完成后用实际媒体时间校正并持久化；较早 seek 的回调通过 token 排除。动画不创建或重新激活音频会话。

## 系统媒体实现

- AVAudioSession 使用 playback/default/longFormAudio，后台 audio 配置保留。只有播放操作激活会话。
- PlayerStore 统一维护 MPNowPlayingInfoCenter。缓存歌曲静态信息和 MPMediaItemArtwork，动态更新时长、位置、速度和队列索引；常规进度校正间隔为五秒，暂停、seek、切歌、路由和前后台变化主动同步。系统根据位置和速度推进锁屏进度，不需要逐帧重发信息。
- MPRemoteCommandCenter 保留播放、暂停、切换、上一首、下一首、位置跳转。按队列可用性启用命令，未支持的跳过区间命令关闭。每个 PlayerStore 仅注册一次，释放时移除 target 和观察者。正式应用仍只有一个 PlayerStore。
- 来电中断记录播放意图，只有系统允许且用户未主动取消时恢复；用户在中断期间暂停会取消待恢复意图。旧输出设备断开时暂停，其他路由变化重新同步系统信息。
- 媒体服务重置后重建 AVPlayer 及其观察者，恢复队列与位置并保持暂停，等待用户播放。不重复注册系统命令。
- 音量继续由 MPVolumeView 提供，输出选择继续由 AVRoutePickerView 提供。没有添加自绘锁屏、控制中心、私有 API 或重复的 Live Activity。

## 本轮文件清单

| 文件 | 改动 |
| --- | --- |
| Flamingo/PlayerMotion.swift | 动画参数、状态机、共享矩形与呈现 modifier |
| Flamingo/RootView.swift | 顶层容器、共享封面、导航协调、MiniPlayer 进度与图标反馈 |
| Flamingo/NowPlayingView.swift | 手势接入、封面目标测量、歌词可见性与布局缓存 |
| Flamingo/PlayerStore.swift | 系统信息缓存、seek 校正、媒体服务重置与观察者生命周期 |
| Flamingo/AnimatedArtwork.swift | 图片过渡、视频显示准备状态及播放调用去重 |
| Flamingo/Design.swift | 按压动画参数及静态封面过渡 |
| Flamingo/FlamingoApp.swift | 前后台系统播放信息同步 |
| Flamingo/Info.plist、project.yml | ProMotion 配置 |
| FlamingoTests/PlayerMotionTests.swift | 接管、反向、预测释放与过期完成回调测试 |
| FlamingoTests/PlayerTests.swift | 暂停 seek、系统元数据和媒体重置测试 |
| FlamingoUITests/FlamingoUITests.swift | 等待稳定状态、取消收起、按钮隔离和导航保留用例 |

之前轮次的字体系统及历史/统计删除改动继续保留，不属于本轮新增功能。

## 验证与限制

Windows 静态检查及 macOS/Xcode 16.4 真机 Release 归档均通过；Core 18 项、原生单元测试 26 项、UI 12 项共 56 项通过，详见 VALIDATION.zh-CN.md 与构建 https://github.com/xu-68/music-player/actions/runs/40706373884 。已完成模拟器回归，未运行真实设备或 Instruments，不能声称已达到 Apple Music 相同动画曲线或实测 60/120fps。

在 macOS 执行 `bash ios/scripts/build.sh test` 后，仍需真机检查快速反复展开/收起、弹簧中途接管、半程反向、切歌、歌词和队列页收起、键盘与旋转、辅助功能大字号及减弱动态效果。系统集成需要实测锁屏、控制中心、AirPods/蓝牙、有线拔出、AirPlay、来电中断和系统开发者菜单的 Reset Media Services。单元测试中发送通知只能验证应用响应路径，不能替代真正的媒体服务重启。

当前通过缩放完整播放器布局实现容器变换，独立封面保持比例；控件在中段开始淡入。不同尺寸下的视觉节奏与中途触摸接管仍需截图、录屏和真机验证。超长歌词的首次完整布局成本仍是此前文档记录的实机性能检查项。

## 官方 API 依据

- [SwiftUI Animatable](https://developer.apple.com/documentation/swiftui/animatable)
- [Now Playing 位置与系统时间推进](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfopropertyelapsedplaybacktime)
- [媒体服务重置处理](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification)
- [ProMotion 适配](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)

最终真机交付：IPA 提交 `73a74c55201173702a78e0ded644f8c586807e3e`，设备归档与包校验通过；最终封面微调版模拟器回归仍在 https://github.com/xu-68/music-player/actions/runs/40710233062 运行。按用户要求先交付真机测试，不等待该任务。此前 56 项通过对应 cc13c27，详见 VALIDATION.zh-CN.md。
