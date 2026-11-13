#!/usr/bin/env bash
# Installs the Gremlo hook for every Claude Code session on this laptop.
# Appends to existing hooks instead of replacing them, and is safe to run twice.
# Run from the repo root: bash scripts/install-hooks.sh
set -euo pipefail
command -v jq >/dev/null || { echo "Needs jq: brew install jq"; exit 1; }

mkdir -p ~/.gremlo
cp apps/mac/Sources/Gremlo/Resources/gremlo-hook.sh ~/.gremlo/gremlo-hook.sh
chmod +x ~/.gremlo/gremlo-hook.sh

settings=~/.claude/settings.json
mkdir -p ~/.claude
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" ~/.claude/settings.backup.json

tmp="$(mktemp)"
jq -s '
  .[0] as $a | .[1] as $b
  | $a + {hooks: (reduce ($b.hooks | keys[]) as $k (($a.hooks // {});
      .[$k] = ((.[$k] // []) as $cur
        | $cur + [ $b.hooks[$k][] | select(. as $e | $cur | index($e) | not) ])))}
' "$settings" pet-hooks.user-settings.json > "$tmp"
jq -e . "$tmp" >/dev/null
mv "$tmp" "$settings"

echo "Hooks installed. Backup at ~/.claude/settings.backup.json"
jq -r '.hooks | to_entries[] | "\(.key): \(.value | length) hook(s)"' "$settings"
