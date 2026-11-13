# Team setup (do this once per laptop)

## 1. Repo
1. Create an empty repo, add a licence (MIT) and `.gitignore` with `.env*`, `.DS_Store`, build folders.
2. Copy `CLAUDE.md`, `.claude/settings.json` and `docs/AI_USAGE.md` into the repo root. Commit.

## 2. Plugins and skills (inside Claude Code)
Ponytail, two prompts:
```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```
gstack (needs Bun 1.4.2+): follow the install prompt in github.com/garrytan/gstack. Use only `/plan-eng-review`, `/review`, `/qa`, `/investigate`, `/verify`. The rest are switched off in `.claude/settings.json`.

Sponsor skills:
- 0G: github.com/0gfoundation/0g-agent-skills (compute account-management is the one for the self-funding loop)
- Mac app person only: github.com/e-palmisano/macos-dev

After installing, run `/skills` and check that the off list matches real names; fix any that differ. Run `/skill-doctor` to see what each skill costs.

## 3. Pet hooks (user level, so the pet sees every Claude Code session)
```
bash scripts/install-hooks.sh
```
This copies the hook to `~/.gremlo/`, backs up `~/.claude/settings.json`, and adds the 9 hooks next to any you already have. Don't use `jq '.[0] * .[1]'`: it replaces arrays, so it would delete your existing hooks for the same events. Then open `claude`, run `/hooks` to confirm, send one prompt, and check `tail -n 3 ~/.gremlo/events.log`.
- Every event is logged to `~/.gremlo/events.log` as metadata only: time, event, session ID, tool name, notification type. No prompts, commands or file contents. Needs `jq` or `python3`. That's the wait-time data for the pitch. Turn it on now, even before the pet app exists.
- Then it POSTs to the pet on `127.0.0.1:47474`. `curl -m 1 ... || true` means a closed pet app never slows or breaks Claude Code.
- It never returns a decision, so permissions behave exactly as normal.

## 4. Habits for low token use
- `/clear` between tasks.
- Sonnet for routine work, Opus for the 0G funding loop and the notch window.
- One teammate per worktree/branch. Commit every 30-60 min.
- Log AI use in `docs/AI_USAGE.md` as you go, not at 7 AM.
