#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=7.1.5
HASH=de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f
OUTPUT="$ROOT/Build/Decoder/FlamingoDecoder.xcframework"
if [[ -d "$OUTPUT" ]]; then exit 0; fi
mkdir -p "$ROOT/Build/Decoder"
cd "$ROOT/Build/Decoder"
curl --fail --location --retry 3 "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz" -o source.tar.xz
echo "$HASH  source.tar.xz" | shasum -a 256 -c -
tar -xf source.tar.xz
for SDK in iphoneos iphonesimulator; do
    PLATFORM=ios
    if [[ "$SDK" == iphonesimulator ]]; then PLATFORM=ios-simulator; fi
    SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
    TARGET=arm64-apple-ios17.0
    if [[ "$SDK" == iphonesimulator ]]; then TARGET=arm64-apple-ios17.0-simulator; fi
    PREFIX="$ROOT/Build/Decoder/$SDK"
    mkdir -p "$PREFIX/build" "$PREFIX/Headers"
    cd "$PREFIX/build"
    "$ROOT/Build/Decoder/ffmpeg-$VERSION/configure" \
      --prefix="$PREFIX" --arch=aarch64 --target-os=darwin --enable-cross-compile \
      --cc="$(xcrun --sdk "$SDK" --find clang)" --sysroot="$SYSROOT" \
      --extra-cflags="-target $TARGET -fPIC" --extra-ldflags="-target $TARGET" \
      --disable-programs --disable-doc --disable-debug --disable-shared --enable-static \
      --disable-autodetect --disable-network --disable-avdevice --disable-avfilter \
      --disable-swscale --disable-postproc --disable-encoders --disable-muxers \
      --disable-hwaccels --disable-videotoolbox --disable-audiotoolbox \
      --disable-protocols --enable-protocol=file --disable-asm \
      --disable-decoders --enable-decoder='aac,aac_fixed,aac_latm,ac3,alac,als,amrnb,amrwb,ape,atrac1,atrac3,atrac3p,cook,dca,eac3,flac,gsm,mp1,mp2,mp3,mp3float,mpc7,mpc8,opus,pcm_*,ralf,shorten,sipr,tak,truehd,truespeech,tta,vorbis,wavpack,wmalossless,wmapro,wmav1,wmav2,wmavoice,adpcm_*'
    make -j "$(sysctl -n hw.ncpu)" > "$PREFIX/build.log" 2>&1 || { tail -100 "$PREFIX/build.log"; exit 1; }
    make install >> "$PREFIX/build.log" 2>&1
    xcrun --sdk "$SDK" clang -target "$TARGET" -isysroot "$SYSROOT" -O2 -fPIC \
      -I"$PREFIX/include" -I"$ROOT/Decoder" -c "$ROOT/Decoder/FlamingoDecoder.c" -o "$PREFIX/wrapper.o"
    xcrun libtool -static -o "$PREFIX/libFlamingoDecoder.a" "$PREFIX/wrapper.o" \
      "$PREFIX/lib/libavformat.a" "$PREFIX/lib/libavcodec.a" "$PREFIX/lib/libswresample.a" "$PREFIX/lib/libavutil.a"
    cp "$ROOT/Decoder/FlamingoDecoder.h" "$ROOT/Decoder/module.modulemap" "$PREFIX/Headers/"
done
xcodebuild -create-xcframework \
  -library "$ROOT/Build/Decoder/iphoneos/libFlamingoDecoder.a" -headers "$ROOT/Build/Decoder/iphoneos/Headers" \
  -library "$ROOT/Build/Decoder/iphonesimulator/libFlamingoDecoder.a" -headers "$ROOT/Build/Decoder/iphonesimulator/Headers" \
  -output "$OUTPUT"
