#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:-simulator}"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This build requires macOS and Xcode. Windows cannot compile iOS binaries." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo 'Install and select Xcode first.' >&2; exit 1; }
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 1; }
xcodegen generate --spec project.yml
mkdir -p Build
STAMP="$(date +%Y%m%d-%H%M%S)"

case "$MODE" in
  simulator)
    xcodebuild -project Flamingo.xcodeproj -scheme Flamingo -configuration Debug \
      -destination 'generic/platform=iOS Simulator' -derivedDataPath Build/DerivedData \
      CODE_SIGNING_ALLOWED=NO build
    ;;
  test)
    (cd Packages/FlamingoCore && swift test)
    if [[ -z "${SIMULATOR_UDID:-}" ]]; then
      SIMULATOR_UDID="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for k,a in d["devices"].items() if "iOS" in k for v in a if "iPhone" in v["name"] and v.get("isAvailable")))')"
    fi
    xcodebuild -project Flamingo.xcodeproj -scheme Flamingo -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" -derivedDataPath Build/DerivedData \
      -resultBundlePath "Build/Tests-$STAMP.xcresult" CODE_SIGNING_ALLOWED=NO test
    ;;
  unsigned)
    ARCHIVE="Build/Flamingo-$STAMP.xcarchive"
    xcodebuild -project Flamingo.xcodeproj -scheme Flamingo -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
    PACKAGE="$(mktemp -d "${TMPDIR:-/tmp}/flamingo-ipa.XXXXXX")"
    trap 'rm -rf "$PACKAGE"' EXIT
    mkdir -p "$PACKAGE/Payload"
    ditto "$ARCHIVE/Products/Applications/Flamingo.app" "$PACKAGE/Payload/Flamingo.app"
    ditto -c -k --keepParent "$PACKAGE/Payload" "$ROOT/Build/Flamingo-unsigned.ipa"
    echo 'Created Build/Flamingo-unsigned.ipa. This is unsigned and requires signing before installation.'
    ;;
  signed)
    : "${TEAM_ID:?Set TEAM_ID to your Apple development team identifier}"
    : "${BUNDLE_ID:?Set BUNDLE_ID to your registered app bundle identifier}"
    : "${EXPORT_OPTIONS_PLIST:?Set EXPORT_OPTIONS_PLIST to your Xcode export options plist}"
    ARCHIVE="Build/Flamingo-signed-$STAMP.xcarchive"
    xcodebuild -project Flamingo.xcodeproj -scheme Flamingo -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
      DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      -allowProvisioningUpdates archive
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath Build/Signed \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" -allowProvisioningUpdates
    ;;
  *) echo 'Usage: bash scripts/build.sh [simulator|test|unsigned|signed]' >&2; exit 2 ;;
esac
