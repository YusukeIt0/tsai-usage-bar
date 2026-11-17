#!/bin/sh
# Builds "TSAI UsageBar.app" and per-architecture release zips into dist/.
#   scripts/build-app.sh [version]
# Signing: uses $SIGN_IDENTITY (Developer ID Application) when set, otherwise ad-hoc.
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-$(cat VERSION)}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP_NAME="TSAI UsageBar"
DIST="dist"

swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release"

rm -rf "$DIST"
mkdir -p "$DIST"
APP="$DIST/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TSAIUsageBar" "$APP/Contents/MacOS/TSAIUsageBar"
cp "$BIN/tsai-usagebar-hook" "$APP/Contents/MacOS/tsai-usagebar-hook"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

sign() {
  if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"
  else
    codesign --force --sign - "$1"
  fi
}
sign "$APP/Contents/MacOS/tsai-usagebar-hook"
sign "$APP"
codesign --verify --strict "$APP"

# Per-architecture zips (smaller downloads); the installer picks one.
for ARCH in arm64 x86_64; do
  WORK="$DIST/$ARCH"
  mkdir -p "$WORK"
  ditto "$APP" "$WORK/$APP_NAME.app"
  for EXE in TSAIUsageBar tsai-usagebar-hook; do
    lipo "$WORK/$APP_NAME.app/Contents/MacOS/$EXE" -thin "$ARCH" -output "$WORK/$EXE.thin"
    mv "$WORK/$EXE.thin" "$WORK/$APP_NAME.app/Contents/MacOS/$EXE"
  done
  sign "$WORK/$APP_NAME.app/Contents/MacOS/tsai-usagebar-hook"
  sign "$WORK/$APP_NAME.app"
  ditto -c -k --keepParent "$WORK/$APP_NAME.app" "$DIST/TSAI-UsageBar-$VERSION-$ARCH.zip"
  rm -rf "$WORK"
done

(cd "$DIST" && shasum -a 256 TSAI-UsageBar-*.zip > SHA256SUMS)
echo "Built $APP ($VERSION)"
cat "$DIST/SHA256SUMS"
