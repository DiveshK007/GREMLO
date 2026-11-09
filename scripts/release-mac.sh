#!/usr/bin/env bash
# Builds Notchi.app (universal), signs it with a Developer ID, wraps it in a dmg, notarizes and staples the dmg.
#   SIGN_ID         "Developer ID Application: Name (TEAMID)"   (security find-identity -v -p codesigning)
#   NOTARY_PROFILE  a notarytool keychain profile, made once with:
#                   xcrun notarytool store-credentials notchi --apple-id you@x.com --team-id TEAMID --password <app-specific password>
# Without SIGN_ID it signs ad hoc and skips notarization: fine for your own Mac, Gatekeeper blocks it elsewhere.
set -euo pipefail
cd "$(dirname "$0")/../apps/mac"
VERSION="${VERSION:-0.2.0}"
BUNDLE_ID="${BUNDLE_ID:-app.notchi.mac}"
OUT="$PWD/dist"
SCRATCH="${TMPDIR:-/tmp}/notchi-release-build" # never the .build a running `swift run` uses
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}" --scratch-path "$SCRATCH"
BIN="$(swift build -c release "${ARCHS[@]}" --scratch-path "$SCRATCH" --show-bin-path)"
APP="$OUT/Notchi.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/assets"
cp "$BIN/Notchi" "$APP/Contents/MacOS/Notchi"
cp Sources/Notchi/Resources/notchi-hook.sh "$APP/Contents/Resources/"
cp -R assets/pets "$APP/Contents/Resources/assets/pets"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Notchi</string>
  <key>CFBundleExecutable</key><string>Notchi</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "SIGN_ID not set: ad hoc signature, no notarization (runs on this Mac only)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

DMG="$OUT/Notchi-$VERSION.dmg"
hdiutil create -quiet -volname Notchi -srcfolder "$APP" -ov -format UDZO "$DMG"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE (see the top of this script)}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
echo "built $DMG"
