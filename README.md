# music-player

The project owner authorizes routine source changes and necessary build fixes to be uploaded to this public repository. See [project collaboration authorization](AGENTS.md).

Native iOS reconstruction of Flamingo v2.1.0 using SwiftUI, UIKit, AVFoundation and a locally compiled FFmpeg audio decoder. iOS 17+, iPhone and iPad. No Android framework or cross-platform UI runtime.

Includes Music folder scanning, advanced LRC/TTML lyrics, local animated artwork, complete queue and sleep controls, playlist editing with duplicates/custom covers/pins, artist releases, interactive player transitions, adaptive native controls, and restrained haptic feedback. Playback history, statistics and their backups have been removed. Online artwork lookup is excluded at the user's request.

Current source release: music 2.3.0 (5). See the [consolidated release notes](ios/RELEASE-2.3.0.zh-CN.md). The ARM64 IPA archive and all 56 core/native/UI regression tests passed in the [validated build](https://github.com/xu-68/music-player/actions/runs/40706373884). Real-device haptics, hardware routing and frame-rate measurements remain unverified.

See [features and build instructions](ios/README.zh-CN.md), [source-based parity audit](ios/PARITY.md), and [actual validation results](ios/VALIDATION.zh-CN.md).

GitHub Actions builds a verified unsigned ARM64 IPA and runs core, native playback/decoder and UI regression tests. The IPA requires signing before installation. Simulator test coverage does not establish real-device performance or exact visual and animation parity.

Based on ideas and behavior from [Flamingo](https://github.com/shouryadixitisverycool/Flamingo), upstream v2.1.0 / `290a792`. GPL-3.0; see LICENSE. FFmpeg 7.1.5 is built reproducibly from official source without GPL or nonfree components.

Final device-test delivery: 2.3.0 (5), commit `73a74c55201173702a78e0ded644f8c586807e3e`. Device archive and package verification passed. The final cover-only refinement has a simulator run still in progress; the owner requested immediate IPA delivery for real-device testing. See ios/VALIDATION.zh-CN.md.
