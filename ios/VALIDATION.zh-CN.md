# 验证记录

日期：2026-10-22。

| 检查 | 结果 |
| --- | --- |
| 14 个 Swift 文件的 Tree-sitter 语法解析 | 通过；不等于 Swift 类型检查 |
| Swift 源码行尾空白检查 | 通过 |
| XcodeGen 源码/Package 路径、YAML 格式 | 通过；未运行 XcodeGen 本体 |
| Info.plist 与工程配置一致性 | 通过 |
| 隐私清单、资产 JSON、PNG 签名 | 通过 |
| 内置许可与上游 LICENSE 一致性 | 通过 |
| 原生源码包排除 Android 工程和本地验证工具 | 已生成独立源码 ZIP |
| 9 项 Swift Core 测试 | 已编写，待 macOS 执行 |
| 2 项原生 UI/播放交互与截图测试 | 已编写，待模拟器执行 |
| iOS 编译 / archive / IPA | 未执行；当前 Windows 无 Xcode/iOS SDK |
| GitHub Fork / 推送 / Actions 运行 | 未执行；当前 GitHub 插件未连接，无可用写入授权 |
| 真机后台、锁屏、蓝牙、AirPlay、导入 | 未验证 |
| 与原 Flamingo / Apple Music 的截图与视频对照 | 未验证 |
| 帧率、包体大小、内存、能耗 | 未测量 |

下一步通过用户选择的 GitHub Actions macOS 路线执行构建。工作流首先运行 Core 与 UI 测试，通过后才生成未签名设备 IPA；失败时保留测试结果。运行成功后需在此记录实际工作流链接、提交号、测试结果与产物；不能用“已配置”替代“已通过”。
