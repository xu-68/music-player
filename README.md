# music-player

The project owner authorizes routine source changes and necessary build fixes to be uploaded to this public repository. See [project collaboration authorization](AGENTS.md).

Native iOS reconstruction of Flamingo v2.1.0 using SwiftUI, UIKit, AVFoundation and a locally compiled FFmpeg audio decoder. iOS 17+, iPhone and iPad. No Android framework or cross-platform UI runtime.

Includes Music folder scanning, advanced LRC/TTML lyrics, local animated artwork, complete queue and sleep controls, playlist editing with duplicates/custom covers/pins, artist releases, interactive player transitions, adaptive native controls, and restrained haptic feedback. Playback history, statistics and their backups have been removed. Online artwork lookup is excluded at the user's request.

Current source release: music 2.3.0 (5). See the [consolidated release notes](ios/RELEASE-2.3.0.zh-CN.md). This version's IPA build and native test results are pending; previous validation records apply only to their recorded commits.

See [features and build instructions](ios/README.zh-CN.md), [source-based parity audit](ios/PARITY.md), and [actual validation results](ios/VALIDATION.zh-CN.md).

GitHub Actions builds a verified unsigned ARM64 IPA and runs core, native playback/decoder and UI regression tests. The IPA requires signing before installation. Simulator test coverage does not establish real-device performance or exact visual and animation parity.

Based on ideas and behavior from [Flamingo](https://github.com/shouryadixitisverycool/Flamingo), upstream v2.1.0 / `290a792`. GPL-3.0; see LICENSE. FFmpeg 7.1.5 is built reproducibly from official source without GPL or nonfree components.
