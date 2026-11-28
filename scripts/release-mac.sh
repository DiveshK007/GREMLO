#!/usr/bin/env bash
# Builds Gremlo.app (universal), signs it with a Developer ID (hardened runtime, Gremlo.entitlements), wraps it in a
# dmg, notarizes and staples the dmg.
#   SIGN_ID         "Developer ID Application: Name (TEAMID)"   (security find-identity -v -p codesigning)
#   notarizing      either NOTARY_PROFILE, a notarytool keychain profile made once with
#                   xcrun notarytool store-credentials gremlo --apple-id you@x.com --team-id TEAMID --password <app-specific password>
#                   or APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD in the environment (release.yml)
# Without SIGN_ID it signs ad hoc and skips notarization: fine for your own Mac, Gatekeeper blocks it elsewhere.
#   SPARKLE_PUBLIC_KEY  the EdDSA public key for auto-update (docs/RELEASE.md); without it the app has no updater
#   SPARKLE_FEED    the appcast URL (default: the appcast.xml attached to the latest GitHub release)
#   ARCH=native     build for this Mac only (install.sh); default is universal (arm64 + x86_64)
#   NO_DMG=1        stop after Gremlo.app (install.sh)
set -euo pipefail
cd "$(dirname "$0")/../apps/mac"
# without VERSION (install.sh), the newest release named in CHANGELOG.md, so a source build reports a real number
VERSION="${VERSION:-$(sed -n 's/^## v\([0-9][0-9.]*\) .*/\1/p' ../../CHANGELOG.md | head -1)}"
VERSION="${VERSION:-0.0.0}"
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
# Sparkle is linked, so every build carries it; only a build with SPARKLE_PUBLIC_KEY turns the updater on
mkdir -p "$APP/Contents/Frameworks" && ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
FEED="${SPARKLE_FEED:-https://github.com/DiveshK007/GREMLO/releases/latest/download/appcast.xml}"
UPDATES=""
if [ -n "${SPARKLE_PUBLIC_KEY:-}" ]; then
  UPDATES="<key>SUFeedURL</key><string>$FEED</string><key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/><key>SUAutomaticallyUpdate</key><true/>"
fi
cp Sources/Gremlo/Resources/gremlo-hook.sh Sources/Gremlo/Resources/gremlo-git-hook.sh "$APP/Contents/Resources/"
# shared assets at the repo root: species packs and the Inter font for the plate
cp -R ../../assets/pets "$APP/Contents/Resources/assets/pets"
cp -R ../../assets/fonts "$APP/Contents/Resources/assets/fonts"
for d in sounds props haptics; do cp -R "../../assets/$d" "$APP/Contents/Resources/assets/$d"; done
# the app icon (logo pack, option B) and the menu bar's template mark
iconutil -c icns ../../assets/icon/Gremlo.iconset -o "$APP/Contents/Resources/Gremlo.icns"
mkdir -p "$APP/Contents/Resources/assets/icon" && cp ../../assets/icon/menubar*.png "$APP/Contents/Resources/assets/icon/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Gremlo</string>
  <key>CFBundleExecutable</key><string>Gremlo</string>
  <key>CFBundleIconFile</key><string>Gremlo</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Gremlo</string><key>CFBundleURLSchemes</key><array><string>gremlo</string></array></dict></array>
  <key>NSAppleEventsUsageDescription</key><string>You turned on Bops to music in Settings. Every 5 seconds Gremlo asks Music and Spotify whether something is playing, so your pet can bob along. It reads the track name for that check and does not keep or send it.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Five minutes before a meeting the pet checks its watch. Event titles never leave this Mac.</string>
  $UPDATES
</dict></plist>
PLIST

if [ -n "${SIGN_ID:-}" ]; then
  # nested code first, inside out (Sparkle's helpers, then the framework, the CLI), then the bundle
  sign() { codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@"; }
  FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign "$FW/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
  sign "$FW/Autoupdate"
  sign "$FW/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/MacOS/gremlo-cli"
  codesign --force --options runtime --timestamp --entitlements Gremlo.entitlements --sign "$SIGN_ID" "$APP"
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
  if [ -n "${NOTARY_PROFILE:-}" ]; then AUTH=(--keychain-profile "$NOTARY_PROFILE")
  else AUTH=(--apple-id "${APPLE_ID:?set NOTARY_PROFILE or APPLE_ID (see the top of this script)}" --team-id "${APPLE_TEAM_ID:?}" --password "${APPLE_APP_PASSWORD:?}"); fi
  # --wait exits 0 whatever Apple decided, so read the status and print Apple's log when it isn't Accepted
  xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait --output-format json > "$OUT/notary.json"
  if [ "$(plutil -extract status raw -o - "$OUT/notary.json")" != Accepted ]; then
    cat "$OUT/notary.json"
    xcrun notarytool log "$(plutil -extract id raw -o - "$OUT/notary.json")" "${AUTH[@]}" || true
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  # what Gatekeeper decides for a downloaded copy: the dmg, then the app inside it
  spctl --assess --type open --context context:primary-signature -v "$DMG"
  spctl --assess --type execute -v "$APP"
fi
echo "built $DMG"
