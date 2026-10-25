"""Export the standalone native repository without the Android reference or local caches."""
import shutil
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent
TARGET = SOURCE.parent.parent / "music-player"
if TARGET.exists():
    raise SystemExit(f"Refusing to overwrite an existing directory: {TARGET}")
TARGET.mkdir()
shutil.copytree(SOURCE, TARGET / "ios", ignore=shutil.ignore_patterns(
    ".validation-tools", ".build", ".swiftpm", "Build", "__pycache__", "*.xcodeproj", "*.xcworkspace", "*.p12", "*.mobileprovision", "ExportOptions.local.plist"))
shutil.copy2(SOURCE.parent / "LICENSE", TARGET / "LICENSE")
(TARGET / ".github/workflows").mkdir(parents=True)
shutil.copy2(SOURCE.parent / ".github/workflows/ios.yml", TARGET / ".github/workflows/ios.yml")
(TARGET / "README.md").write_text(
    "# music-player\n\n"
    "A native iOS local music player inspired by Flamingo's classic Apple Music-style interactions. "
    "Built with SwiftUI, UIKit, AVFoundation and MediaPlayer. iOS 17 or later. No third-party runtime dependencies.\n\n"
    "See [implementation and build instructions](ios/README.zh-CN.md), "
    "[design notes](ios/DESIGN-NOTES.zh-CN.md) and [validation status](ios/VALIDATION.zh-CN.md).\n\n"
    "GitHub Actions runs core and simulator tests, archives the device app, and uploads a verified unsigned ARM64 IPA. "
    "The unsigned IPA requires signing before installation.\n\n"
    "Inspired by [Flamingo](https://github.com/shouryadixitisverycool/Flamingo). GPL-3.0; see LICENSE.\n",
    encoding="utf-8")
(TARGET / ".gitignore").write_text(".DS_Store\n.tools/\n*.zip\n", encoding="utf-8")
(TARGET / ".gitattributes").write_text("* text=auto\n*.sh text eol=lf\n*.swift text eol=lf\n*.yml text eol=lf\n*.png binary\n", encoding="utf-8")
print(f"Exported standalone native sources to {TARGET}")
