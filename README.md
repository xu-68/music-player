# music-player

A native iOS local music player inspired by Flamingo's classic Apple Music-style interactions. Built with SwiftUI, UIKit, AVFoundation and MediaPlayer. iOS 17 or later. No third-party runtime dependencies.

See [implementation and build instructions](ios/README.zh-CN.md), [design notes](ios/DESIGN-NOTES.zh-CN.md) and [validation status](ios/VALIDATION.zh-CN.md).

GitHub Actions runs core and simulator tests, archives the device app, and uploads a verified unsigned ARM64 IPA. The unsigned IPA requires signing before installation.

Inspired by [Flamingo](https://github.com/shouryadixitisverycool/Flamingo). GPL-3.0; see LICENSE.

Validated build: [GitHub Actions run 40224260658](https://github.com/xu-68/music-player/actions/runs/40224260658), source commit `9531386`. All 10 core tests and 2 simulator UI/playback tests passed. The unsigned ARM64 device IPA is 441,399 bytes and requires iOS 17 or later.

Native screenshots from the iPhone 16 Pro simulator use explicitly generated, isolated test music and artwork; these fixtures are excluded from Release builds. Screenshots are available in [docs/screenshots](docs/screenshots). This demonstrates native rendering and test coverage, not a completed pixel-by-pixel or real-device performance comparison with Apple Music.
