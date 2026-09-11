#!/usr/bin/env bash
#
# Builds Mac Duo.app from the SwiftPM package.
#
#   ./build.sh            build and sign
#   ./build.sh --run      build, sign, and relaunch the app
#   ./build.sh --universal  build for Apple Silicon and Intel
#
# Signs with the first Apple Development identity in the keychain, so macOS
# keeps the Screen Recording permission across rebuilds. Without one it signs
# ad-hoc, and macOS may require the permission again after rebuilding. Set
# SIGN_IDENTITY to use another identity, or to - for ad-hoc signing.

set -euo pipefail
cd "$(dirname "$0")"

TIMESTAMP=--timestamp
if [[ -z "${SIGN_IDENTITY+x}" ]]; then
  # awk reads to the end, so security never fails on a closed pipe.
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/"Apple Development: / && !found { print $2; found = 1 }' || true)"
  # A development build needs no secure timestamp, so it also signs offline.
  TIMESTAMP=--timestamp=none
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == - ]]; then
  TIMESTAMP=--timestamp=none
fi
APP_NAME="Mac Duo"
BUNDLE="build/${APP_NAME}.app"

BUILD_ARGS=(-c release)
RUN_APP=false
for argument in "$@"; do
  case "$argument" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --run) RUN_APP=true ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

swift build "${BUILD_ARGS[@]}" --product MacDuo
swift build "${BUILD_ARGS[@]}" --product lidprobe

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/MacDuo"
PROBE="$BIN_PATH/lidprobe"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp LICENSE NOTICE "$BUNDLE/Contents/Resources/"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp "$PROBE" build/lidprobe

codesign --force --options runtime "$TIMESTAMP" \
  --sign "$SIGN_IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"

echo "built ${BUNDLE}"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

if "$RUN_APP"; then
  pkill -x MacDuo 2>/dev/null || true
  sleep 0.5
  open "$BUNDLE"
  echo "launched"
fi
