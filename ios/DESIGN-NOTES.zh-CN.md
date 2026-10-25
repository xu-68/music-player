# 从 Flamingo 提炼的原生实现规则

用户目标是研究原实现的思路后重写，iOS 不承接 Android 架构、插件接口和兼容层。视觉基准为上游 `v2.1.0` 的经典 Apple Music 风格，非 Liquid Glass。

| 原项目线索 | 观察与意图 | iOS 实现位置 |
| --- | --- | --- |
| `ui/pages/NowPlaying.kt` Album，约 839 行 | 播放使用 stiffness 300 / dampingRatio 1 的弹簧；暂停使用 350ms EaseOutQuart，并增加封面边距。重点是封面仿佛有重量地退后，不能只有按钮换图标。 | `NowPlayingView` 使用暂停缩放 0.83、350ms 曲线、播放弹簧和关联阴影。两种动画系统参数不能一一等值，需要视频校准。 |
| `ui/widgets/basic/ShadowImage.kt` | 使用连续圆角、图像质量分级、缓存及独立封面阴影。 | `ArtworkView`、`ArtworkCache`；导入封面缩到最长 1000px，缓存限定约 32MB，原生 Image 绘制。 |
| `ui/widgets/effects/YosFloatingLightView.kt` | 背景直接来自封面，低频缓动约 12 秒，依据前台状态和播放状态暂停。 | `FlowingArtworkBackground` 以低更新频率的 TimelineView 缩放/缓转模糊封面；前后台、暂停、偏好与减弱动态效果决定是否运行。 |
| `ui/widgets/YosLyricView.kt` | 歌词是带时间轴的交互，不是循环播放的装饰；当前行聚焦，周围行降低对比并模糊，逐字激活，滚动跟随且允许用户接管。 | 独立 `LyricsParser`、`LyricsView`、`KaraokeLine`；真实播放时钟、二分检索当前行、单词遮罩插值、点击 seek、手动滚动暂停跟随。 |
| `ui/pages/HomeNav.kt` 和 `docs/pics/1.png`–`3.png` | 主页/资料库/统计三个入口，底部迷你播放器比内容层更稳定。 | RootView 保留三个独立 NavigationStack 和自定义经典标签布局，使用原生材质，不依赖新版系统自动更换 TabView 外观。 |
| `docs/pics/4.png` | 大封面、标题/艺人、独立进度、宽松控制区、歌词/输出/队列工具区。 | NowPlayingView 按安全区与可用尺寸布局，横屏改为左右分布。系统音量和输出使用 MPVolumeView / AVRoutePickerView。 |

## 动画和性能约束

- 迷你播放器和全屏封面共用 matchedGeometryEffect；关闭手势使用真实拖动距离与预测终点。它不是固定时长的视频或模拟动画。
- 当前播放时间独立在 PlaybackProgressView 与 LyricsView 读取，避免 10Hz 时钟驱动全屏封面布局；歌词解析只在切歌/换歌词时执行。
- 背景仅在全屏播放器存在时创建，封面从缓存读取，背景运动根据生命周期暂停。GPU 模糊和实际能耗仍必须使用 Instruments 检查。
- 全局转场使用弹簧；逐字遮罩短线性插值用于连接播放时钟采样，避免每个字突变。减弱动态效果时取消背景运动、缩小位移并减少插值。
- 不把原项目截图里的商业封面和音乐当作应用内置数据；导入真实用户文件后自然使用其封面。UI 测试素材另行生成并隔离。

## 后续视觉验收

使用同一设备尺寸、同一首歌曲、同一封面和同一播放时间截图。逐项比较安全区、封面大小、文字行高、控制区间距、背景取色、转场速度和中途反向拖动。静态语法检查和 UI 测试流程均不能证明像素或运动曲线一致。

当前仓库静态截图不足以准确推断所有原始动画；未经过真机和视频对比的参数均为首轮实现，不能写成已完成一比一还原。
