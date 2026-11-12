#!/usr/bin/env bash
# Claude Code hook. Logs only metadata (no prompts, commands or file contents) for the
# wait-time numbers, then forwards the event to the local app.
# Every event is fire-and-forget, except PermissionRequest: that one waits (at most 110 s) for an answer the
# user gives on the notch, menu bar, phone or Watch, and prints it. No answer, no output: Claude Code then
# shows its normal prompt. The app never decides on its own.
dir="$HOME/.notchi"
mkdir -p "$dir"
payload="$(cat)"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$payload" | jq -c --arg ts "$(date +%s)" \
    '{ts: ($ts|tonumber), event: .hook_event_name, session: .session_id, tool: .tool_name, notification: .notification_type}' \
    >> "$dir/events.log" 2>/dev/null
elif command -v python3 >/dev/null 2>&1; then
  printf '%s' "$payload" | python3 -c '
import json, sys, time
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
keep = {"ts": int(time.time()), "event": d.get("hook_event_name"), "session": d.get("session_id"),
        "tool": d.get("tool_name"), "notification": d.get("notification_type")}
print(json.dumps(keep, separators=(",", ":")))
' >> "$dir/events.log" 2>/dev/null
fi
event="$(printf '%s' "$payload" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -n1)"
if [ "$event" = "PermissionRequest" ]; then
  answer="$(printf '%s' "$payload" | curl -s -m 110 -X POST -H 'Content-Type: application/json' \
    --data-binary @- http://127.0.0.1:47474/claude/permission 2>/dev/null || true)"
  case "$answer" in *hookSpecificOutput*) printf '%s' "$answer" ;; esac
  exit 0
fi
printf '%s' "$payload" | curl -s -m 1 -X POST -H 'Content-Type: application/json' \
  --data-binary @- http://127.0.0.1:47474/claude/hook >/dev/null 2>&1 || true
exit 0
