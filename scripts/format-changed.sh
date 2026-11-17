#!/usr/bin/env bash
# Prettier check on the files a change touched. The code base is hand-formatted (dense one-liners, compact CSS), so the
# whole tree is not enforced: new and rewritten files are, and old files move over as they are edited.
# Usage: scripts/format-changed.sh <base-commit>
set -euo pipefail
base="${1:-}"
if [ -z "$base" ] || [[ "$base" =~ ^0+$ ]]; then echo "no base commit to compare with; skipping"; exit 0; fi
files=$(git diff --name-only --diff-filter=ACMR "$base"...HEAD -- 'apps/server/src/*.ts' 'apps/web/app/*.ts' 'apps/web/app/*.tsx' 'apps/web/components/*.tsx' 'apps/web/lib/*.ts' 'packages/brain/*.js' || true)
if [ -z "$files" ]; then echo "no files to check"; exit 0; fi
echo "$files" | xargs npx prettier --check
