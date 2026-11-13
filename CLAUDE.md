# Gremlo

A desktop AI pet that has to earn its own food. It lives on the Mac screen edge and in a home behind a door in the notch. It reacts live to Claude Code / Codex sessions, holds the sponsored line on a little sign while the agent works, and pays for its own thinking from what it earns.

Started at ETHGlobal Mumbai 2026 (Classic, from scratch); that build is kept on the `ethglobal-0g` branch.

## Gremlo 1.0 (branch `main`)
The design export in `docs/design/1.0/` is the source of truth (rounds 2-4 extend the base spec; later rounds win).
The build plan and progress live in `docs/PLAN_1.0.md`. Windows/Linux and the Rust core are out of scope for now.
Product copy names no chain ("purse", "earned", "paid for thinking"); account IDs and hashes appear only in Advanced views, docs and the README.

## Stack (what the live loop must prove)
- **NEAR testnet:** the vault contract (`contracts-near`, deployed as `vault.gremlo.testnet`) holds campaigns and each pet's compute budget. Brands fund campaigns; settled views credit the pet's budget; the next thought is paid from it. Tx hashes for every step, in PROOF.md. Spend cap. Degrades gracefully when low, never crashes.
- **NEAR AI (TEE inference):** pet decisions and ad lines in the main flow, request ID shown for every call.
- **World ID:** one human one pet (anti click-fraud), owner approves spends above the cap, backend proof check, visible denied path.
- Accounts, env var names and next steps: `HANDOFF.md`. `BUILD_GUIDE.md` describes the ETHGlobal 0G build, not main.

## Repo layout
- `apps/mac/` Swift app: transparent overlay window, notch door, sprites, menu-bar popover, local hook server
- `apps/web/` brand checkout, dashboard, pet registration (IDKit), owner approvals, pet page
- `apps/ios/` iPhone and Watch apps; `apps/vscode/`, `apps/raycast/` extensions
- `packages/brain/` NEAR AI calls, mood tiers, job profit check
- `apps/server/` campaigns, World verify, approvals, impression settlement, signed sightings log
- `contracts-near/` the vault (campaigns, compute budget); `contracts-accounts/` factory and purse (not deployed)
- `contracts/` Foundry CampaignVault.sol from the ETHGlobal 0G build, not used on main

## Pet state machine (Claude Code hook -> pet)
Hooks POST to `http://127.0.0.1:47474/claude/hook`. The server must answer fast.
Approvals (1.0): only a `PermissionRequest` may get a decision back, and only one the user gave on a surface (notch, menu bar, phone, Watch). Nothing ever decides for the user. Commands that delete, push or spend money get no keyboard shortcut and always need a click. Answering in the terminal still works and wins; the other surfaces grey out.

| Hook event | Pet state |
|---|---|
| SessionStart | wakes behind the door |
| UserPromptSubmit | door opens, drops out, "on it" |
| PreToolUse / PostToolUse | working, holds the ad sign |
| PermissionRequest / Notification permission_prompt | jumps, waves "need approval" flag, sound |
| Notification idle_prompt | taps foot, looks at user |
| Stop | celebrates; after idle timeout, climbs side wall to notch and goes home |
| StopFailure | trips, sad face |
| SessionEnd | goes home, door locks |

Money overlays every state: full = bouncy, low = slow and thin, broke = cannot leave the notch.

## Mood tiers (from the real compute budget, never a fake number)
- Thriving: best model, full animations
- Stable: cheaper model
- Hungry: cheapest model, refuses unprofitable jobs
- Asleep: no paid calls; local animation only, says why

## Never fake (hard rules)
- No mocked balances, request IDs, tx hashes or payments in the main demo flow.
- Seeded or simulated data is labelled on screen as seeded.
- The LLM never authorises a payment. A deterministic budget check does.
- If NEAR AI is unreachable: safe-stop and say so. Never invent a decision.
- Never claim "self-funded" unless the full loop ran with no manual top-up.

## Code rules
- Write the minimum that works. Reuse before adding a dependency.
- Money: integer minor units, never floats. One test for any money or budget logic.
- Secrets only in `.env` (gitignored). Never print keys, never commit them.
- No emoji in code or logs. Comments only where the why is not obvious.
- No "AI-sounding" prose in README or UI copy. Plain, short, specific.

## Git
- Small commits, every 30-60 min, real messages describing the change.
- Never one big dump. ETHGlobal disqualifies missing or single-commit histories.
- Work on your own branch/worktree; merge to main often.

## AI usage (required by ETHGlobal)
Log notable AI-assisted work in `docs/AI_USAGE.md` as you go: tool, what it produced, what a human changed.

## Demo constraints
- ETHGlobal video: 2-4 min, 720p+, laptop recording, own voice, no speed-up, no AI voiceover.
