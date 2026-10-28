"""Validate the committed app icon without replacing user-supplied artwork."""
import struct
from pathlib import Path
icon = Path(__file__).resolve().parent.parent / "Flamingo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
data = icon.read_bytes()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
assert struct.unpack(">II", data[16:24]) == (1024, 1024)
assert data[25] == 2, "App icon must be opaque RGB"
print(f"Validated user-supplied icon: {icon}")
