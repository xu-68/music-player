#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/FlamingoTests/Fixtures"
mkdir -p "$TARGET"
# Synthetic tones, generated in CI; no commercial recordings or downloaded media.
for CONFIG in 'wmav2:wma' 'vorbis:ogg' 'opus:opus' 'flac:flac' 'wavpack:wv'; do
    CODEC="${CONFIG%%:*}"
    EXTENSION="${CONFIG##*:}"
    ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=0.2' \
      -metadata title='Decoder fixture' -metadata artist='Flamingo Tests' \
      -ac 2 -ar 48000 -strict -2 -c:a "$CODEC" "$TARGET/tone.$EXTENSION"
done
