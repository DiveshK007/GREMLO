#!/usr/bin/env bash
# Builds Gremlo.app (universal), signs it with a Developer ID, wraps it in a dmg, notarizes and staples the dmg.
#   SIGN_ID         "Developer ID Application: Name (TEAMID)"   (security find-identity -v -p codesigning)
#   NOTARY_PROFILE  a notarytool keychain profile, made once with:
#                   xcrun notarytool store-credentials gremlo --apple-id you@x.com --team-id TEAMID --password <app-specific password>
# Without SIGN_ID it signs ad hoc and skips notarization: fine for your own Mac, Gatekeeper blocks it elsewhere.
#   ARCH=native     build for this Mac only (install.sh); default is universal (arm64 + x86_64)
#   NO_DMG=1        stop after Gremlo.app (install.sh)
set -euo pipefail
cd "$(dirname "$0")/../apps/mac"
VERSION="${VERSION:-0.2.0}"
BUNDLE_ID="${BUNDLE_ID:-app.gremlo.mac}"
OUT="$PWD/dist"
SCRATCH="${TMPDIR:-/tmp}/gremlo-release-build" # never the .build a running `swift run` uses
if [ "${ARCH:-universal}" = native ]; then ARCHS=""; else ARCHS="--arch arm64 --arch x86_64"; fi

# shellcheck disable=SC2086 # ARCHS is a flag list or empty
swift build -c release $ARCHS --scratch-path "$SCRATCH"
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCHS --scratch-path "$SCRATCH" --show-bin-path)"
APP="$OUT/Gremlo.app"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/assets"
cp "$BIN/Gremlo" "$APP/Contents/MacOS/Gremlo"
cp "$BIN/GremloCLI" "$APP/Contents/MacOS/gremlo-cli"
cp Sources/Gremlo/Resources/gremlo-hook.sh Sources/Gremlo/Resources/gremlo-git-hook.sh "$APP/Contents/Resources/"
# shared assets at the repo root: species packs and the Inter font for the plate
cp -R ../../assets/pets "$APP/Contents/Resources/assets/pets"
cp -R ../../assets/fonts "$APP/Contents/Resources/assets/fonts"
for d in sounds props haptics; do cp -R "../../assets/$d" "$APP/Contents/Resources/assets/$d"; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Gremlo</string>
  <key>CFBundleExecutable</key><string>Gremlo</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Gremlo</string><key>CFBundleURLSchemes</key><array><string>gremlo</string></array></dict></array>
  <key>NSAppleEventsUsageDescription</key><string>Only if you turn on Bops to music: Gremlo asks Music and Spotify for the playing track's name.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Five minutes before a meeting the pet checks its watch. Event titles never leave this Mac.</string>
</dict></plist>
PLIST

if [ -n "${SIGN_ID:-}" ]; then
  # nested code first (the CLI), then the bundle
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/MacOS/gremlo-cli"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  echo "SIGN_ID not set: ad hoc signature, no notarization (runs on this Mac only)"
  codesign --force --sign - "$APP/Contents/MacOS/gremlo-cli"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
if [ -n "${NO_DMG:-}" ]; then echo "built $APP"; exit 0; fi

# the dmg window shows the app next to an Applications link, to drag it across
DMG="$OUT/Gremlo-$VERSION.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE" && ditto "$APP" "$STAGE/Gremlo.app" && ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Gremlo -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE (see the top of this script)}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
echo "built $DMG"
