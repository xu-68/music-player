# v2.1.0 功能与交付验收

基线：上游 `290a79213da1f6bf61803bb6b822d444e0dc74d2`。本文件是实施清单，未通过的项目不能作为“完整成品”交付。

| 功能组 | 原版依据 | 验收要求 | 状态 |
|---|---|---|---|
| 页面与动画 | Home / Library / Stats / NowPlaying / YosLyricView | 六个主界面、大小播放器转场、跟手收起、暂停封面缩放、背景运动、歌词运动 | 补齐与对照中 |
| 音乐扫描 | MusicLibrary / Overview | 导入文件、目录授权、递归扫描、重复去重、刷新、短音频过滤、同名歌词与视频匹配 | 补齐中 |
| 资料库 | MusicList / LocalAlbums / LocalArtists | 标题/时长/艺人/修改日期排序、升降序、搜索、艺人拆分、关注艺人 | 补齐中 |
| 歌单 | PlayLists / PlayListEditModal / PendingPlayListDeletion | 创建/编辑/搜索/排序、自动拼图封面、队列操作、删除可撤销 | 补齐中 |
| 队列 | NowPlaying PlayingList | 下一首/最后播放、拖动排序、滑动删除和移至下一首、随机/三种循环、重启恢复 | 补齐中 |
| 音频 | MediaController / FadeExo / YosRenderFactory | 系统播放与 FFmpeg 兜底、格式信息、200ms 淡入淡出、中断、耳机、锁屏 | 补齐中 |
| 睡眠定时 | SleepTimer / SleepTimerSheet | 时长/本首结束/队列结束、延长、取消、剩余时间、0/5/10/30 秒淡出 | 补齐中 |
| 歌词发现 | MediaController / YosTtmlFactory / YosLrcFactory | 内嵌与同名外置、TTML 优先且失败回退 LRC、格式兼容 | 补齐中 |
| 高级歌词 | LyricFormatSupport_en.md | 多时间戳、逐字、重叠行共同聚焦、对唱、翻译/音译切换、字体权重/平衡/模糊 | 补齐中 |
| 动态封面 | AnimatedArtworkLibrary / AnimatedAlbumCoverOverlay | 本地视频、可选原接口搜索/缓存、专辑黑名单、关闭时释放/清理缓存 | 补齐中 |
| 历史与统计 | ListenHistoryManager / ListenStatsLibrary | 最近 50 首与开关、日/周/月/年/全部、歌曲/艺人/专辑排名、删除文件后保留统计 | 补齐中 |
| 数据备份 | StatsDataSection / ListenStatsManager | 统计导出、合并/覆盖导入、去重、清空确认；原版导出 JSON 兼容导入 | 补齐中 |
| 界面设置 | SettingsLibrary / UserInterfaceSetting | 深浅色、音量条、背景、栏材质、歌词设置、圆角、动态封面设置 | 补齐中 |
| 小组件 | README 声明；Android Manifest 未找到 AppWidgetProvider | 原生 WidgetKit 显示当前歌曲并打开/控制播放，签名须具备 App Group | 实施中 |
| 安卓专属 | StatusBarLyric / NotificationSetting / ExoPlayerSettings | Xposed/LSPosed、Android 通知图标、MediaCodec/AudioTrack 参数不可直接用于 iOS；用锁屏、音频路由和原生解码设置提供对应能力，不伪造无效开关 | 平台边界须明确 |
| 构建测试 | 原版源码 + Swift 测试 + 原生截图 | 功能回归、设备 ARM64 归档、模拟器测试、逐项实际结果、未签名 IPA 标注 | 执行中 |

历史首版的 12 项测试只证明当时覆盖的路径，不等于本表已经验收。新版本必须以新提交的测试、构建和产物重新验收。仅有首版截图不足以证明动画一比一；视觉误差与未能实际验证的硬件能力需要如实保留。
