#!/bin/sh
# Builds "TSAI UsageBar.app" and per-architecture release zips into dist/.
#   scripts/build-app.sh [version]
# Signing: uses $SIGN_IDENTITY (Developer ID Application) when set, otherwise ad-hoc.
#   $SIGN_KEYCHAIN  optional keychain that holds the identity (must be unlocked)
#   $NOTARY_PROFILE optional notarytool keychain profile; with it, the per-architecture
#                   apps are notarized and stapled before they are zipped
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-$(cat VERSION)}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP_NAME="TSAI UsageBar"
DIST="dist"
if [ -n "${NOTARY_PROFILE:-}" ] && [ -z "${SIGN_IDENTITY:-}" ]; then
  echo "NOTARY_PROFILE needs SIGN_IDENTITY: only Developer ID builds can be notarized." >&2
  exit 1
fi

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
mkdir -p "$APP/Contents/Resources/Languages"
cp Resources/Languages/*.json "$APP/Contents/Resources/Languages/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

sign() {
  if [ -n "${SIGN_IDENTITY:-}" ]; then
    if [ -n "${SIGN_KEYCHAIN:-}" ]; then
      codesign --force --options runtime --timestamp --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" "$1"
    else
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"
    fi
  else
    codesign --force --sign - "$1"
  fi
}
sign "$APP/Contents/MacOS/tsai-usagebar-hook"
sign "$APP"
codesign --verify --strict "$APP"

# Per-architecture apps (smaller downloads); the installer picks one.
for ARCH in arm64 x86_64; do
  WORK="$DIST/apps/$ARCH"
  mkdir -p "$WORK"
  ditto "$APP" "$WORK/$APP_NAME.app"
  for EXE in TSAIUsageBar tsai-usagebar-hook; do
    lipo "$WORK/$APP_NAME.app/Contents/MacOS/$EXE" -thin "$ARCH" -output "$WORK/$EXE.thin"
    mv "$WORK/$EXE.thin" "$WORK/$APP_NAME.app/Contents/MacOS/$EXE"
  done
  sign "$WORK/$APP_NAME.app/Contents/MacOS/tsai-usagebar-hook"
  sign "$WORK/$APP_NAME.app"
  codesign --verify --strict "$WORK/$APP_NAME.app"
done

# Notarize both thinned apps in one submission, then staple each. The tickets
# must match the exact signatures that go into the zips.
if [ -n "${NOTARY_PROFILE:-}" ]; then
  SUBMISSION="$DIST/notarization.zip"
  RESULT="$DIST/notarization.json"
  ditto -c -k --keepParent "$DIST/apps" "$SUBMISSION"
  if [ -n "${SIGN_KEYCHAIN:-}" ]; then
    set -- --keychain-profile "$NOTARY_PROFILE" --keychain "$SIGN_KEYCHAIN"
  else
    set -- --keychain-profile "$NOTARY_PROFILE"
  fi
  xcrun notarytool submit "$SUBMISSION" "$@" --wait --timeout 1h --output-format json > "$RESULT" || true
  STATUS=$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo unknown)
  if [ "$STATUS" != "Accepted" ]; then
    echo "Notarization result: $STATUS" >&2
    ID=$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || true)
    [ -n "$ID" ] && xcrun notarytool log "$ID" "$@" >&2 || cat "$RESULT" >&2
    exit 1
  fi
  for ARCH in arm64 x86_64; do
    xcrun stapler staple "$DIST/apps/$ARCH/$APP_NAME.app"
    xcrun stapler validate "$DIST/apps/$ARCH/$APP_NAME.app"
    spctl --assess --type execute --verbose=2 "$DIST/apps/$ARCH/$APP_NAME.app" 2>&1 | grep -q "source=Notarized Developer ID" ||
      { echo "Gatekeeper did not accept the $ARCH app as notarized." >&2; exit 1; }
  done
  rm -f "$SUBMISSION" "$RESULT"
fi

for ARCH in arm64 x86_64; do
  ditto -c -k --keepParent "$DIST/apps/$ARCH/$APP_NAME.app" "$DIST/TSAI-UsageBar-$VERSION-$ARCH.zip"
done
rm -rf "$DIST/apps"

(cd "$DIST" && shasum -a 256 TSAI-UsageBar-*.zip > SHA256SUMS)
echo "Built $APP ($VERSION)"
cat "$DIST/SHA256SUMS"
