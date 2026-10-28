# v2.1.0 功能对照与验收

参照上游 `290a79213da1f6bf61803bb6b822d444e0dc74d2`。下表记录实际代码与测试入口；最终运行结果见 VALIDATION.zh-CN.md，不能用首版 12 项测试代替本轮验证。

| 功能组 | 原版依据 | iOS 实现与验证入口 |
|---|---|---|
| 首页 | Home / ListenHistoryManager | 随机 5 首推荐、最近 50 首、连续同专辑历史合并；RecentMusic / HomeView，核心分组测试与原生截图 |
| 资料库 | Library / MusicLibrary / Overview | 四入口；按用户本轮要求统一为 Documents/Music 原文件扫描、自动/手动扫描、子文件夹、同步删除；AudioTests 扫描、迁移、删除及路径边界回归 |
| 艺人与专辑 | ArtistLibrary / ArtistInfo / AlbumInfo | 拆分与关注、主艺人歌曲、专辑/单曲 EP/参与发行、排序搜索、整组收藏/入队/加入歌单；ArtistCatalog 核心测试 |
| 歌单 | PlayLists / PlayListEditModal / PlayListSearch | 描述、照片、自适应拼图、重复歌曲、逐项/批量删除、重排、模糊搜索、置顶排序、整组队列操作、删除撤销；UI 创建/重复项/重启持久化测试 |
| 队列 | NowPlaying PlayingList / MusicLibrary PlayStatus | 队列条目独立身份、下一首/最后、重排、删除/移至下一首、清空、随机/循环、恢复；核心队列与 PlayerTests/UI 进度恢复 |
| 音频 | FadeExo / YosRenderFactory | 系统解码 + FFmpeg 软件兜底、保留原文件、格式信息、200ms 淡入淡出、后台/中断/耳机/锁屏/AirPlay；AudioTests 解码与导入，PlayerTests 真实播放 |
| 睡眠定时 | SleepTimer / SleepTimerSheet | 倒计时/本首/队列结束、延长/取消、剩余时间、0/5/10/30 秒淡出；PlayerTests 三种实际停止测试与 UI 设置测试 |
| 歌词发现 | MediaController / YosLrcFactory / YosTtmlFactory | 内嵌或同名歌词、TTML 优先及失败 LRC 回退、UTF-8/16；AudioTests 文件夹同名歌词回退 |
| 歌词呈现 | LyricFormatSupport_en.md / YosLyricView | 多时间戳、逐字、翻译/音译、重叠行、v1/v2、间奏、系统 Bold 字体与自然换行、点击定位、跟随；核心解析测试与真实播放器 UI |
| 动态封面 | AnimatedArtworkLibrary / AnimatedAlbumCoverOverlay | 按用户要求整套移除；使用静态专辑封面 |
| 统计与备份 | ListenStatsTracker / ListenStatsLibrary / ListenStatsManager | 过半计数、实际媒体时间、跨日分段、历史开关、五周期、三排行、删除后保留标签、原版 JSON 导入/合并/覆盖/导出/清空；核心往返与去重、PlayerTests 统计写入 |
| 外观和动画 | SettingsLibrary / NowPlaying / HomeNav | 深浅色、音量条、背景/栏模糊、圆角；共享封面、下拉收起、暂停缩放、背景运动、歌词过渡；UI 截图与后续真机视频对照 |

## 按用户选择与平台对应

- 用户要求整套移除动态封面；视频导入、扫描匹配、播放和黑名单均已删除。
- Android 的 Xposed/LSPosed 状态栏歌词、通知图标、AudioTrack/MediaCodec 参数没有对应的 iOS API。系统播放能力使用 iOS 锁屏、后台音频、系统音量和音频路由；不设置无作用的仿制开关。
- 按用户本轮要求，音乐唯一入口为“文件”App 内 Flamingo/Music。直接使用原文件，不再提供音乐文件选择器或外部目录授权；应用内确认删除同时删除 Music 中对应源文件。
- README 提及 widgets，但原版 Manifest 未发现 AppWidgetProvider。源码 `ui/widgets` 属应用内控件，没有据此虚构上游已有桌面小组件，也没有额外加入 WidgetKit/App Group 依赖。

## 验收规则

1. 最新源代码必须通过 Core、iOS 解码/播放、UI 操作测试和 ARM64 归档；不能拿失败或旧提交的 IPA 交付。
2. 原生截图证明实际渲染与可见布局；自动测试证明覆盖路径的行为。它们不能独立证明像素和动画时间曲线与原版一致。
3. 后台/蓝牙/AirPlay、最大辅助字号、iPad 和真机掉帧/能耗需有实际设备记录。没有这些证据时必须明确保留，不得写“真机全部通过”或“120 FPS”。
4. 未签名 IPA 明确标注需要签名；源码、工作流提交和测试产物必须可互相追溯。
