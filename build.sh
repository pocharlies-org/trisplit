#!/usr/bin/env bash
# Builds ./Trisplit.app (native Swift engine + panel) and signs it.
#
# Signing identity, first match wins:
#   1. TRISPLIT_SIGN_ID (+ optional TRISPLIT_KEYCHAIN)
#   2. "trisplit dev" from the dedicated keychain created by scripts/dev-cert.sh
#   3. ad-hoc (Accessibility permission resets on every rebuild)
set -euo pipefail
cd "$(dirname "$0")"

APP=Trisplit.app
BIN=Trisplit
VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION" ] || { echo "error: empty VERSION file" >&2; exit 1; }
# shellcheck source=scripts/dev-keychain.sh
. scripts/dev-keychain.sh

shopt -s nullglob
SRCS=(app/main.swift app/Core/*.swift app/Engine/*.swift app/Shell/*.swift)
shopt -u nullglob

for f in panel.html icon.png VERSION; do
    [ -f "$f" ] || { echo "error: missing $f" >&2; exit 1; }
done

# Compile outside the bundle so a failed build keeps the previous app intact.
mkdir -p build
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 \
    -framework AppKit -framework WebKit -framework Carbon \
    -framework ApplicationServices -framework ServiceManagement \
    "${SRCS[@]}" -o "build/$BIN"

# Assemble and sign outside the repo: ~/Documents may be File Provider managed and
# re-tags bundle dirs with FinderInfo xattrs mid-sign, which codesign rejects as
# "detritus".
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
S="$STAGE/$APP"
mkdir -p "$S/Contents/MacOS" "$S/Contents/Resources"
mv "build/$BIN" "$S/Contents/MacOS/$BIN"
cp -X panel.html icon.png "$S/Contents/Resources/"

cat >"$S/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.dibanez.trisplit</string>
  <key>CFBundleName</key><string>Trisplit</string>
  <key>CFBundleDisplayName</key><string>Trisplit</string>
  <key>CFBundleExecutable</key><string>Trisplit</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.dibanez.trisplit.url</string>
      <key>CFBundleURLSchemes</key><array><string>trisplit</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
plutil -lint "$S/Contents/Info.plist" >/dev/null

SIGN=()
if [ -n "${TRISPLIT_SIGN_ID:-}" ]; then
    SIGN=(-s "$TRISPLIT_SIGN_ID")
    if [ -n "${TRISPLIT_KEYCHAIN:-}" ]; then SIGN+=(--keychain "$TRISPLIT_KEYCHAIN"); fi
elif [ -f "$DEV_KC" ] && [ -f "$DEV_PW" ]; then
    # codesign only finds identities in searched keychains; the partition list set
    # by dev-cert.sh lets it use the key without a GUI prompt.
    dev_add_to_search_list || { echo "error: cannot add $DEV_KC to the keychain search list; run 'make cert'" >&2; exit 1; }
    security unlock-keychain -p "$(cat "$DEV_PW")" "$DEV_KC"
    SHA="$(dev_identity_sha)"
    [ -n "$SHA" ] || { echo "error: no '$DEV_NAME' identity in $DEV_KC; run 'make cert'" >&2; exit 1; }
    SIGN=(--keychain "$DEV_KC" -s "$SHA")
fi
if [ ${#SIGN[@]} -eq 0 ]; then
    echo "WARNING: no signing identity; signing ad-hoc." >&2
    echo "WARNING: macOS will RESET the Accessibility permission on every rebuild." >&2
    echo "WARNING: run 'make cert' (scripts/dev-cert.sh) once to get a stable identity." >&2
    SIGN=(-s -)
fi

xattr -cr "$S"
codesign --force --options runtime --timestamp=none "${SIGN[@]}" "$S"
codesign --verify --deep --strict "$S"
codesign -dv --verbose=2 "$S" 2>&1 | grep -E '^(Identifier|Authority|Signature)=' || true

rm -rf "$APP"
ditto --norsrc --noextattr "$S" "$APP"
echo "built: $PWD/$APP"
