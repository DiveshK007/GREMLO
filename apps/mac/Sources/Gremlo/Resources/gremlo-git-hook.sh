#!/usr/bin/env bash
# gremlo git hook
# Installed as post-commit, pre-push and reference-transaction. Sends one line per event to the local app:
# {"type":"git","event":"<name>","repo":"<hash of the repo path>"}. No messages, no diffs, no file names.
# A hook that was here before runs first, unchanged, and its exit status is kept.
name="$(basename "$0")"
input=""
case "$name" in pre-push|reference-transaction) input="$(cat)" ;; esac
status=0
if [ -x "$0.gremlo-prev" ]; then
  printf '%s' "$input" | "$0.gremlo-prev" "$@"
  status=$?
fi
# installed globally (core.hooksPath): git skips the repo's own .git/hooks, so run that one too
gitdir="$(git rev-parse --git-dir 2>/dev/null)"
here="$(cd "$(dirname "$0")" && pwd -P)"
if [ -n "$gitdir" ] && [ -x "$gitdir/hooks/$name" ] && [ "$here" != "$(cd "$gitdir/hooks" 2>/dev/null && pwd -P)" ]; then
  printf '%s' "$input" | "$gitdir/hooks/$name" "$@" || status=$?
fi
top="$(git rev-parse --show-toplevel 2>/dev/null)"
repo="$(printf '%s' "$top" | shasum -a 256 | cut -c1-16)"
send() {
  line="{\"type\":\"git\",\"event\":\"$1\",\"repo\":\"$repo\"}"
  sink="${GREMLO_GIT_SINK:-$NOTCHI_GIT_SINK}"  # the old name is read for one release
  if [ -n "$sink" ]; then printf '%s\n' "$line" >> "$sink"; return; fi
  curl -s -m 1 -X POST -H 'Content-Type: application/json' --data "$line" http://127.0.0.1:47474/git >/dev/null 2>&1 || true
}
zero="0000000000000000000000000000000000000000"
case "$name" in
  post-commit) send commit ;;
  pre-push)
    # a force push: the remote's current commit is not an ancestor of what we push
    printf '%s\n' "$input" | while read -r lref lsha rref rsha; do
      [ -z "$lsha" ] && continue
      case "$rsha" in ""|$zero*) continue ;; esac
      case "$lsha" in $zero*) continue ;; esac
      if ! git merge-base --is-ancestor "$rsha" "$lsha" 2>/dev/null; then send force-push; break; fi
    done ;;
  reference-transaction)
    if [ "$1" = "committed" ]; then
      printf '%s\n' "$input" | while read -r old new ref; do
        case "$old" in $zero*) case "$ref" in refs/tags/v*) send tag ;; esac ;; esac
      done
    fi ;;
esac
exit $status
