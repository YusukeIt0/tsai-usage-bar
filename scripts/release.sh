#!/bin/sh
# Builds the app and publishes a GitHub Release with per-architecture zips and SHA256SUMS.
#   scripts/release.sh            uses the version in VERSION
# Requires a Developer ID build that Apple has notarized:
#   SIGN_IDENTITY   "Developer ID Application: … (TEAM)" identity
#   NOTARY_PROFILE  notarytool keychain profile
#   SIGN_KEYCHAIN   optional keychain holding both (must be unlocked)
set -eu
cd "$(dirname "$0")/.."
TEAM_ID="27K9A27SGR"
VERSION=$(cat VERSION)
[ -z "$(git status --porcelain)" ] || { echo "Working tree is not clean." >&2; exit 1; }
[ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ] ||
  { echo "Set SIGN_IDENTITY and NOTARY_PROFILE: releases must be Developer ID signed and notarized." >&2; exit 1; }
swift test
scripts/build-app.sh "$VERSION"

# Check the exact apps users download.
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"' EXIT
for ZIP in dist/TSAI-UsageBar-"$VERSION"-*.zip; do
  rm -rf "$CHECK/unpacked"
  ditto -x -k "$ZIP" "$CHECK/unpacked"
  APP="$CHECK/unpacked/TSAI UsageBar.app"
  codesign --verify --strict "$APP"
  INFO=$(codesign -dvv "$APP" 2>&1)
  printf '%s\n' "$INFO" | grep -q "^Authority=Developer ID Application: " &&
    printf '%s\n' "$INFO" | grep -qx "TeamIdentifier=$TEAM_ID" ||
    { echo "$ZIP is not Developer ID signed by $TEAM_ID." >&2; exit 1; }
  xcrun stapler validate "$APP" >/dev/null || { echo "$ZIP has no notarization ticket." >&2; exit 1; }
  spctl --assess --type execute --verbose=2 "$APP" 2>&1 | grep -q "source=Notarized Developer ID" ||
    { echo "Gatekeeper does not accept $ZIP as notarized." >&2; exit 1; }
done

git tag -a "v$VERSION" -m "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" dist/TSAI-UsageBar-"$VERSION"-*.zip dist/SHA256SUMS \
  --title "TSAI UsageBar $VERSION" --notes-file "docs/release-notes/$VERSION.md"
