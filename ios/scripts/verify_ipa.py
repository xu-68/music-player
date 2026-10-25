"""Check that an IPA contains an actual ARM64 iOS executable, not a simulator build."""
import hashlib
import plistlib
import struct
import sys
from pathlib import Path
from zipfile import ZipFile

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "Build/Flamingo-unsigned.ipa"
with ZipFile(path) as archive:
    if archive.testzip() is not None:
        raise SystemExit("IPA ZIP integrity check failed")
    info_paths = [name for name in archive.namelist() if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
    if len(info_paths) != 1:
        raise SystemExit("IPA must contain exactly one application bundle under Payload")
    info_path = info_paths[0]
    info = plistlib.loads(archive.read(info_path))
    executable_name = info.get("CFBundleExecutable", "")
    if not executable_name or "/" in executable_name or "$" in executable_name:
        raise SystemExit("Invalid application executable name in Info.plist")
    binary = archive.read(info_path.removesuffix("Info.plist") + executable_name)
    if len(binary) < 32:
        raise SystemExit("Application executable is missing or truncated")
    magic, cpu, subtype, filetype, command_count, command_size, flags, reserved = struct.unpack_from("<8I", binary)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or filetype != 2:
        raise SystemExit("Expected a thin ARM64 Mach-O executable")
    if command_size > len(binary) - 32:
        raise SystemExit("Invalid Mach-O load-command bounds")
    offset = 32
    platforms = []
    for _ in range(command_count):
        if offset + 8 > 32 + command_size:
            raise SystemExit("Truncated Mach-O load command")
        command, size = struct.unpack_from("<2I", binary, offset)
        if size < 8 or offset + size > 32 + command_size:
            raise SystemExit("Invalid Mach-O load-command size")
        if command == 0x32:
            if size < 24:
                raise SystemExit("Truncated LC_BUILD_VERSION")
            platforms.append(struct.unpack_from("<I", binary, offset + 8)[0])
        offset += size
    if 2 not in platforms or 7 in platforms:
        raise SystemExit("Executable must target physical iOS devices, not iOS Simulator")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise SystemExit("Bundle does not declare iPhoneOS platform")
    if "audio" not in info.get("UIBackgroundModes", []):
        raise SystemExit("Background audio capability is missing")
    print(f"Verified ARM64 iOS IPA: {path.name}")
    print(f"Bundle: {info.get('CFBundleIdentifier')} | Minimum iOS: {info.get('MinimumOSVersion')}")
print(f"Size: {path.stat().st_size:,} bytes")
print(f"SHA-256: {hashlib.sha256(path.read_bytes()).hexdigest()}")
print("This verifies the device package structure, not signing or runtime behavior.")
