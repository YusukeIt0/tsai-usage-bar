#!/bin/sh
# Builds the app and publishes a GitHub Release with per-architecture zips and SHA256SUMS.
#   scripts/release.sh            uses the version in VERSION
# Set SIGN_IDENTITY to a "Developer ID Application" identity for signed builds;
# notarization is not automated yet, so such builds are still reported as not notarized.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
[ -z "$(git status --porcelain)" ] || { echo "Working tree is not clean." >&2; exit 1; }
swift test
scripts/build-app.sh "$VERSION"
git tag -a "v$VERSION" -m "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" dist/TSAI-UsageBar-"$VERSION"-*.zip dist/SHA256SUMS \
  --title "TSAI UsageBar $VERSION" --notes-file "docs/release-notes/$VERSION.md"
