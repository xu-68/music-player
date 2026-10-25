"""Generate the app icon from geometric primitives using only Python's standard library."""
import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Flamingo/Resources/Assets.xcassets"
ICON = CATALOG / "AppIcon.appiconset"
ICON.mkdir(parents=True, exist_ok=True)

def inside(x, y):
    # A slender note stem, two flags, and an elliptical note head.
    head = ((x - 0.37) / 0.139) ** 2 + ((y - 0.685) / 0.104) ** 2 < 1
    stem = 0.433 <= x <= 0.5 and 0.28 <= y <= 0.69
    flag = 0.48 <= x <= 0.73 and 0.24 + (0.73 - x) * 0.26 <= y <= 0.338 + (0.73 - x) * 0.26
    lower_flag = 0.48 <= x <= 0.68 and 0.39 + (0.68 - x) * 0.24 <= y <= 0.453 + (0.68 - x) * 0.24
    return head or stem or flag or lower_flag

size = 1024
raw = bytearray()
for y in range(size):
    raw.append(0)
    for x in range(size):
        coverage = sum(inside((x + dx) / size, (y + dy) / size) for dx, dy in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]) / 4
        raw.extend(round(a * (1 - coverage) + b * coverage) for a, b in zip((20, 20, 23), (246, 57, 93)))

def chunk(name, data):
    return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
(ICON / "AppIcon.png").write_bytes(png)
(ICON / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
(CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
print(f"Generated {ICON / 'AppIcon.png'}")
