#!/usr/bin/env bash
# Builds Gremlo from source on this Mac and installs it to ~/Applications. Safe to re-run: it updates and replaces.
#   curl -fsSL https://raw.githubusercontent.com/DiveshK007/GREMLO/main/install.sh | bash
# Built here, the app is ad hoc signed and never quarantined, so Gatekeeper doesn't stop it (no notarization needed).
#   GREMLO_SRC      where the source lives (default ~/.gremlo/src; a checkout this script sits in wins)
#   GREMLO_APP_DIR  where Gremlo.app goes (default ~/Applications)
#   GREMLO_NO_OPEN  set to 1 to install without starting it
set -euo pipefail
REPO="${GREMLO_REPO:-https://github.com/DiveshK007/GREMLO.git}"
SRC="${GREMLO_SRC:-$HOME/.gremlo/src}"
DEST="${GREMLO_APP_DIR:-$HOME/Applications}"
APP="$DEST/Gremlo.app"
say() { printf 'gremlo: %s\n' "$*"; }
die() { printf 'gremlo: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Gremlo runs on macOS only."
os="$(sw_vers -productVersion)"
[ "${os%%.*}" -ge 13 ] || die "Gremlo needs macOS 13 or later; this Mac has $os."
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  die "Gremlo builds with the Xcode Command Line Tools. Run: xcode-select --install   then run this again."
fi

# Piped through curl there is no script file, so this only matches when run from a checkout.
here=""
if [ -f "${BASH_SOURCE[0]:-}" ]; then here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
if [ -n "$here" ] && [ -f "$here/apps/mac/Package.swift" ]; then
  SRC="$here"
  say "building from this checkout: $SRC"
elif [ -d "$SRC/.git" ]; then
  say "updating $SRC"
  git -C "$SRC" pull --ff-only --quiet || die "couldn't update $SRC (local changes?). Fix or delete it and run this again."
else
  say "downloading the source to $SRC"
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 --quiet "$REPO" "$SRC"
fi

say "building (a few minutes the first time)"
log="$(mktemp -t gremlo-build)"
ARCH=native NO_DMG=1 "$SRC/scripts/release-mac.sh" >"$log" 2>&1 || { tail -25 "$log" >&2; die "the build failed; nothing was installed. Full log: $log"; }
BUILT="$SRC/apps/mac/dist/Gremlo.app"
codesign --verify --strict "$BUILT" || die "the build isn't signed correctly; nothing was installed."

# Quit only the installed copy, never a `swift run` someone has open.
if pgrep -f "$APP/Contents/MacOS/Gremlo" >/dev/null 2>&1; then
  say "quitting the running Gremlo"
  osascript -e 'tell application id "app.gremlo.mac" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do pgrep -f "$APP/Contents/MacOS/Gremlo" >/dev/null 2>&1 || break; sleep 1; done
  pkill -f "$APP/Contents/MacOS/Gremlo" 2>/dev/null || true
fi

mkdir -p "$DEST"
rm -rf "$APP"
ditto "$BUILT" "$APP"
say "installed $APP"

if [ "${GREMLO_NO_OPEN:-}" = 1 ]; then
  say "not started (GREMLO_NO_OPEN=1). Start it with: open \"$APP\""
else
  open "$APP"
  say "started. It lives in the menu bar and the notch."
fi
say "update: run this again. Remove: Settings, General, disconnect Claude Code; quit from the menu bar; then rm -rf \"$APP\" ~/.gremlo/src"
