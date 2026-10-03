#!/usr/bin/env bash
# Cuts a GitHub release of Trisplit and bumps the Homebrew cask.
#   1. requires a clean tree and a commit already pushed to origin
#   2. builds with the "trisplit dev" identity (refuses ad-hoc)
#   3. zips Trisplit.app -> dist/Trisplit-<VERSION>.zip, sha256
#   4. gh release create v<VERSION> (target = current commit)
#   5. updates Casks/trisplit.rb in pocharlies-org/homebrew-tap and pushes
# Usage: scripts/release.sh   (VERSION file holds the version; RELEASE_NOTES optional env)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=pocharlies-org/trisplit
TAP=pocharlies-org/homebrew-tap
VER="$(tr -d '[:space:]' < VERSION)"
ZIP="dist/Trisplit-$VER.zip"

[ -z "$(git status --porcelain)" ] || { echo "error: working tree not clean" >&2; exit 1; }
SHA="$(git rev-parse HEAD)"
git fetch -q origin
[ -n "$(git branch -r --contains "$SHA")" ] || { echo "error: $SHA is not pushed to origin" >&2; exit 1; }
gh release view "v$VER" --repo "$REPO" >/dev/null 2>&1 && { echo "error: release v$VER already exists" >&2; exit 1; }

# Never ship an ad-hoc build: the Accessibility permission would reset on every update.
unset TRISPLIT_SIGN_ID TRISPLIT_KEYCHAIN
./build.sh
codesign -dv --verbose=2 Trisplit.app 2>&1 | grep -q '^Authority=trisplit dev$' \
    || { echo "error: build is not signed with the 'trisplit dev' identity (run 'make cert')" >&2; exit 1; }
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Trisplit.app/Contents/Info.plist)"
[ "$BUILT" = "$VER" ] || { echo "error: bundle version $BUILT != VERSION $VER" >&2; exit 1; }

mkdir -p dist
rm -f "$ZIP"
ditto -c -k --keepParent Trisplit.app "$ZIP"
SUM="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "zip: $ZIP sha256: $SUM"

NOTES="${RELEASE_NOTES:-Trisplit $VER. Built from commit ${SHA:0:7}.

Install: brew install --cask pocharlies-org/tap/trisplit
The app is signed with a self-signed certificate (not notarized). Grant Accessibility on first launch.}"
gh release create "v$VER" "$ZIP" --repo "$REPO" --target "$SHA" --title "Trisplit $VER" --notes "$NOTES"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh repo clone "$TAP" "$TMP/tap" -- -q
CASK="$TMP/tap/Casks/trisplit.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$VER\"/; s/^  sha256 \".*\"/  sha256 \"$SUM\"/" "$CASK"
git -C "$TMP/tap" add Casks/trisplit.rb
if git -C "$TMP/tap" diff --cached --quiet; then
    echo "cask already up to date"
else
    git -C "$TMP/tap" commit -q -m "trisplit $VER"
    git -C "$TMP/tap" push -q origin HEAD
fi
echo "released v$VER"
