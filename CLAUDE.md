# Notchi

A desktop AI pet that has to earn its own food. It lives on the Mac screen edge and in a home behind a door in the notch. It reacts live to Claude Code / Codex sessions, holds the sponsored line on a little sign while the agent works, and pays for its own 0G inference from what it earns.

ETHGlobal Mumbai 2026, Classic (from scratch). Submission deadline: Sat 7 Nov, 09:00 IST. Freeze features at midnight Fri.

## Sponsors (what each must prove)
- **0G Private Computer:** inference in the main flow, request ID shown for every call.
- **0G Agents That Pay for Themselves:** money in -> credit lands in the pet's own 0G compute account -> next inference paid from it. Tx hashes + request IDs. Spend cap. Degrades gracefully when low, never crashes.
- Campaign contract lives on 0G's chain; brands pay in 0G testnet tokens; the pet auto-deposits its earnings into its own 0G compute account.
- **World (Agent Pass):** one human one pet (anti click-fraud), owner approves spends above the cap, backend proof check, visible denied path.
- **ENS (stretch, only if 0G + World work by midnight):** pet subname, pet key writes status/mood only, only the owner writes the payout address.
- Final lineup: 0G + World + ENS. Full details and checklists: `BUILD_GUIDE.md`.

## Repo layout
- `apps/mac/` Swift app: transparent overlay window, notch door, sprites, menu-bar popover, local hook server
- `apps/web/` brand checkout, dashboard, pet registration (IDKit), owner approvals, pet page
- `packages/brain/` 0G calls, balance reads, mood tiers, job profit check
- `apps/server/` campaigns, World verify, approvals, impression settlement
- `contracts/` Foundry: CampaignVault.sol (0G chain)

## Pet state machine (Claude Code hook -> pet)
Hooks POST to `http://127.0.0.1:47474/claude/hook`. The server must answer fast and never return a decision.

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

## Mood tiers (from the real 0G balance, never a fake number)
- Thriving: best model, full animations
- Stable: cheaper model
- Hungry: cheapest model, refuses unprofitable jobs
- Asleep: no paid calls; local animation only, says why

## Never fake (hard rules)
- No mocked balances, request IDs, tx hashes or payments in the main demo flow.
- Seeded or simulated data is labelled on screen as seeded.
- The LLM never authorises a payment. A deterministic budget check does.
- If 0G is unreachable: safe-stop and say so. Never invent a decision.
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
- 0G video: under 3 min. Target 2:30-2:50 so one cut fits both.
