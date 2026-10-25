"""Package only native sources and the CI workflow, without the Android reference or tooling caches."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT.parent.parent / "Flamingo-iOS-source.zip"
excluded = {".validation-tools", ".build", ".swiftpm", "Build", "__pycache__"}
with ZipFile(OUTPUT, "w", compression=ZIP_DEFLATED) as archive:
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if not path.is_file() or any(part in excluded or part.endswith((".xcodeproj", ".xcworkspace")) for part in relative.parts):
            continue
        if path.suffix in {".p12", ".mobileprovision"} or path.name == "ExportOptions.local.plist":
            continue
        archive.write(path, (Path("ios") / relative).as_posix())
    archive.write(ROOT.parent / "LICENSE", "LICENSE")
    archive.write(ROOT.parent / ".github/workflows/ios.yml", ".github/workflows/ios.yml")
print(f"Created {OUTPUT} ({OUTPUT.stat().st_size:,} bytes)")
