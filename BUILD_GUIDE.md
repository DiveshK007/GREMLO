# Notchi 101 + Build Guide (final lineup)

Read this first, then `CLAUDE.md` (rules for Claude Code) and `SETUP.md` (laptop setup).

ETHGlobal Mumbai 2026, Classic track. Submission: Sat 7 Nov, 09:00 IST. Judging: 09:30. Feature freeze: midnight Fri.

**Decision is final: Notchi, simple version, sponsors 0G + World + ENS. No more idea debates.**

---

## 1. The idea in one breath

Notchi is a desktop AI pet that has to earn its own food.

It lives in a little home behind a hidden door in the MacBook notch. When you send Claude Code a prompt, the door opens and the pet drops out. It reacts live to what the agent is doing: working, waiting for your approval, waiting for input, done, failed. While the agent works, the pet holds up a small sign with one sponsored line. Brands pay for that line on 0G's chain, and the pet gets paid per impression. The pet then pays for its own thoughts, 0G inference, from that money.

- Rich pet: bouncy, smart, uses the best model.
- Broke pet: thin, slow, uses the cheap model.
- Totally broke: it can't leave the notch.

**Pitch line:** "Your coding agent makes you wait. Notchi makes that wait pay for itself."

**Judge line:** "Every pet belongs to a real human (World), thinks and eats on 0G, and can't touch its own wallet (ENS)."

## 2. Only two sides

| Side | What they do | What they get |
|---|---|---|
| Developers | Install the Mac app, add the hooks, verify once with World | A useful status pet for Claude Code (works even with zero ads), and a pet that feeds itself |
| Brands (dev-tool companies) | Fund a campaign, pick one of 3 lines the pet wrote | Their line in front of developers during the agent wait |

Cut, no guilt: creator contest, voting, Whitechain, Codex, Physical AI track.

## 3. The core loop (this is the demo)

1. **Register:** the dev verifies with World ID, the pet gets a wallet and an ENS name (`mochi.notchi.eth`). One human, one pet.
2. **Brand pays:** the brand funds a campaign contract on 0G's chain and picks one of the 3 lines the pet suggested through 0G.
3. **Pet works:** Claude Code runs, and the pet holds the line on its sign. Impressions are counted.
4. **Pet gets paid:** the backend settles impressions, and the contract pays the pet's wallet. It pays only to the address in the pet's ENS record, which only the owner can change.
5. **Pet eats:** the pet automatically deposits from its wallet into its own 0G compute account. The next inference is paid from that money. No human in between.
6. **Pet asks permission for big spends:** above the spend cap (for example, upgrading to the best model), the pet asks its owner. The owner approves with World.
7. **Campaign ends:** unspent budget refunds to the brand.

## 4. Sponsors: one job each

| Sponsor | Job | Prize | Priority |
|---|---|---|---|
| 0G | The pet's brain and its food | Build with 0G PC ($5k) + Agents That Pay ($2k) | Must |
| World | Every pet belongs to a real human, so brands aren't paying bots (click fraud). The owner approves big spends | Agent Pass ($5k) | Must |
| ENS | The leash: the pet updates its own status, but can never change its payout address | ENSv2 ($7k) | Only if 0G + World work by midnight |

If time runs short, cut ENS, never World.

### 4.1 0G checklist
- [ ] Every pet decision goes through a 0G inference call. Show the request ID in the UI for every call.
- [ ] The campaign contract is deployed on 0G's testnet chain; brands pay in 0G testnet tokens.
- [ ] Self-funding loop: payout reaches the pet wallet, the pet auto-deposits into its 0G compute account, and the next call is paid from it. Show the tx hashes and request IDs on screen.
- [ ] Spend cap, enforced in code, never by the LLM.
- [ ] Graceful degrade: lower balance means a cheaper model; zero means asleep, and the pet says why.
- [ ] Safe-stop if 0G is unreachable. Never invent a decision.
- [ ] Episode log on 0G Storage (one entry per decision with the request ID). Nice to have, strengthens PC.
- [ ] 0G video under 3 min.
- [ ] **Confirm at the 0G booth:** that brands paying in 0G testnet tokens on their chain is fine, and the exact SDK call for depositing into a compute account from code.

### 4.2 World checklist (Agent Pass)
- [ ] IDKit in the web app, used for pet registration (action `register-pet`).
- [ ] **Backend validation** of every proof. Never trust the frontend.
- [ ] Nullifier stored. A second pet from the same human is rejected and shown on screen: the denied path.
- [ ] Brands only pay pets with a verified registration (the contract checks a `verified` flag set by the backend).
- [ ] Owner approval: above the spend cap, the pet creates an approval request, the owner proves with World (action `approve-spend`), and only then does the spend happen. A denied or missing proof means no spend.
- [ ] Integration debrief file (`docs/WORLD_DEBRIEF.md`): what worked, what broke.
- [ ] The staging simulator is fine for the demo.

### 4.3 ENS checklist (stretch)
- [ ] Parent name on Sepolia (`notchi.eth` or whatever is available), and a subname per pet.
- [ ] ENSv2 per-record permissions: the pet's key can write text records `status` and `mood` only; only the owner can write `addr` (the payout address).
- [ ] The contract reads the payout address from the pet's ENS name, so changing it needs the owner.
- [ ] Demo the denied path: the pet's key tries to change `addr` and is rejected.
- [ ] Public status: anyone can resolve `mochi.notchi.eth` and see whether that dev's agent is working, hungry or asleep.
- [ ] If ENSv2 per-record permissions aren't usable on Sepolia yet, ask the ENS booth for the closest supported setup. Don't fake it.

## 5. Architecture

```
 Claude Code
   | hooks (curl POST, 1s timeout, never blocks)
   v
 [Mac app]  apps/mac  (Swift)
   - hook server 127.0.0.1:47474
   - overlay + notch door + sprites + state machine
   - menu-bar popover (balances, request IDs, campaign)
   | HTTPS
   v
 [Backend]  apps/server  (Node/TS)
   - campaigns, impressions, settlement signer
   - World proof checks, approvals
   - packages/brain (0G calls, mood, spend cap, auto-deposit)
   |            |                 |              |
   v            v                 v              v
 0G Compute   0G chain          World ID       ENS (Sepolia)
 (inference,  CampaignVault     (one human,    pet names,
  request IDs) + pet payouts     approvals)     status + payout records
   ^
 [Web app]  apps/web  (Next.js)
   - brand checkout + dashboard
   - pet registration (IDKit), owner approvals
   - pet profile page (resolves the ENS name)
```

## 6. Repo layout

```
apps/mac/        Swift: overlay, notch door, sprites, hook server, popover
apps/web/        Next.js: brand checkout, dashboard, registration, approvals, pet page
apps/server/     Node/TS: campaigns, impressions, settlement, World verify, approvals
packages/brain/  0G calls, request IDs, mood tiers, spend cap, auto-deposit, storage log
contracts/       Foundry: CampaignVault.sol (0G chain), tests, deploy scripts
docs/            AI_USAGE.md, WORLD_DEBRIEF.md, demo script, wait-time stats
```

## 7. Mac app (apps/mac)

### 7.1 Window and notch
- Use a borderless, transparent `NSPanel` covering the screen, above normal windows. It joins all Spaces and ignores clicks except on the pet.
- Find the notch from `NSScreen.main.safeAreaInsets.top` and `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. On Macs without a notch, put the door at the top centre under the menu bar.
- The door is a small sprite at the notch's bottom edge, with a 4-6 frame open animation.
- The pet walks the bottom edge, climbs the right wall, walks the top and enters the door.

### 7.2 Hook server
- `POST /claude/hook` on `127.0.0.1:47474`, using `NWListener` or the smallest HTTP lib that works.
- Read `hook_event_name`, `session_id`, `notification_type` and `tool_name`.
- Reply `200` with an empty body immediately. **Never return a decision.**
- Follow the most recent active `session_id`.
- **Also append every event with a timestamp to a local log.** This gives the real wait-time numbers for the pitch (section 12).

### 7.3 State machine

| Hook event | Pet state |
|---|---|
| SessionStart | wakes up behind the door |
| UserPromptSubmit | door opens, drops out, "on it" |
| PreToolUse / PostToolUse | working, holds the ad sign (impression moment) |
| PermissionRequest / Notification `permission_prompt` | jumps, waves the "need approval" flag, sound |
| Notification `idle_prompt` | taps foot, looks at the user |
| Stop | celebrates; after 60-90 s idle climbs the wall and goes home |
| StopFailure | trips, sad face |
| SessionEnd | goes home, door locks |

| Mood | From the real 0G compute balance | Effect |
|---|---|---|
| Thriving | high | bouncy, best model |
| Stable | middle | normal, cheaper model |
| Hungry | low | slow and thin, cheapest model |
| Asleep | zero, or 0G unreachable | stays in the notch, says why |

### 7.4 Popover
Shows the pet name (ENS), mood, wallet balance, 0G compute balance, the current ad line, today's impressions, the last 5 request IDs, the last deposit tx and a pause-ads toggle.

### 7.5 Sprites
Frames for idle, walk, climb, sign, wave, celebrate, trip and sleep. Show thin/slow through playback speed plus a squash. Any characters are fine for the demo; swap to original art before anything public.

## 8. Impressions
- An impression counts when the pet is in the working state, the sign has been visible for at least 5 s, and that pet hasn't counted for that campaign in the last N minutes.
- The Mac app sends impressions signed with a per-install key created at registration.
- Only World-verified pets count.
- The backend batches and settles every 10 min, or on the demo button.
- Say it in the README: impressions are client-reported in v1, and World's one-human-one-pet rule plus rate limits are the defence.

## 9. Contract: CampaignVault.sol (0G chain)

| Function | Who | Does |
|---|---|---|
| `createCampaign(lineHash, rate, endTime)` payable | brand | locks the budget in 0G testnet tokens, emits `CampaignCreated` |
| `topUp(id)` payable | brand | adds budget |
| `setVerified(pet, bool)` | operator | marks a pet as World-verified (set by the backend after the proof check) |
| `settleImpressions(id, pet, count)` | operator | pays `count * rate` to the pet's payout address; verified pets only; never more than what's left |
| `close(id)` | anyone after `endTime` | refunds the remainder to the brand |

- The payout address comes from the pet's ENS `addr` record if ENS is done. Otherwise it's a registry mapping only the owner can set.
- Integer math only. The operator can never pay itself.
- Events for everything.
- Foundry tests: create, settle within budget, settle over budget reverts, unverified pet reverts, refund after end, double close reverts, operator can't redirect a payout.

## 10. 0G brain (packages/brain)
- `think(state)`: current state goes to 0G, returns `{ action, say, line_id }` plus the request ID.
- A deterministic validator checks every action. The LLM never moves money.
- The model is picked by mood.
- `suggestLines(brief)`: 3 ad lines for the brand to choose from (request IDs stored).
- `autoDeposit()`: when the wallet balance is above a threshold, deposit into the 0G compute account, up to the spend cap. Log the tx hash.
- `requestApproval(spend)`: above the cap, creates an approval and waits for the owner's World proof.
- Safe-stop on any error: `{ action: "sleep", reason }`.
- `logEpisode()` to 0G Storage if time allows.

## 11. Backend API (apps/server)

| Route | Purpose |
|---|---|
| `POST /pets/register` | World proof + wallet + install key; rejects a reused nullifier; calls `setVerified` |
| `POST /campaigns/lines` | the pet suggests 3 lines for a brief |
| `GET /campaigns/active` | what the pet shows |
| `POST /impressions` | signed batch from the Mac app |
| `POST /settle/:id` | operator settles onchain (demo button) |
| `POST /approvals` / `POST /approvals/:id/confirm` | spend request, then the owner's World proof |
| `GET /pets/:name` | balances, mood, request IDs, deposits |

## 12. The pitch numbers (start now)
Every teammate turns on hook logging today. The night before the demo, compute:
- total hours the team waited on Claude Code this weekend,
- number of permission prompts and average wait on each,
- how many impressions that would have been.

Open the pitch with it: "Our team waited X hours on Claude Code in one hackathon." Use only real numbers from the log.

## 13. Env vars (names only, values in `.env`, never committed)

```
ZG_API_BASE=        ZG_API_KEY=         ZG_CHAIN_RPC=       ZG_CHAIN_ID=
ZG_PET_PRIVATE_KEY= ZG_OPERATOR_KEY=    ZG_VAULT_ADDRESS=
ZG_STORAGE_RPC=     ZG_STORAGE_INDEXER=
WORLD_APP_ID=       WORLD_ACTION_REGISTER=register-pet   WORLD_ACTION_APPROVE=approve-spend
ENS_RPC_SEPOLIA=    ENS_PARENT_NAME=    ENS_OWNER_KEY=
SERVER_URL=         DATABASE_URL=
```

## 14. Who does what

| Person | Owns |
|---|---|
| A: Mac | notch window, door, sprites, hook server, state machine, popover, wait-time log |
| B: Chain | CampaignVault + tests + deploy on 0G, settlement, then ENS names + permissions |
| C: Web + World | brand checkout, dashboard, IDKit registration + approvals, backend proof checks, denied paths |
| D: Brain | 0G calls, request IDs, mood, spend cap, auto-deposit, server API, README, demo script |

With 3 people: B takes ENS at the end, and C and D share the server.

## 15. Timeline (from 18:00)

| Time (IST) | Goal |
|---|---|
| 18:00-18:30 | Repo + skeletons pushed. Hook logging on for everyone. Quick 0G booth question (section 4.1). |
| 18:30-20:00 | **First things moving:** the pet appears and reacts to 3 hook events; contract compiles with tests; one 0G call shows a request ID; IDKit proof verifies on the backend. |
| 20:00-22:00 | Contract on the 0G chain. Brand checkout pays. Pet shows the line. Registration with the denied path. |
| 22:00-23:30 | Settlement to the pet. Auto-deposit to 0G compute. Mood from the real balance. Owner approval with World. |
| 23:30-00:00 | **Full end-to-end run.** |
| 00:00 | **Feature freeze** for 0G + World. ENS only if everything above works. |
| 00:00-03:00 | ENS (if green), bugs, climb-to-notch animation, sound. |
| 03:00-05:00 | README, AI_USAGE.md, WORLD_DEBRIEF.md, addresses, wait-time numbers, screenshots. |
| 05:00-07:00 | Record the video: own voice, laptop, several takes, no speed-up. |
| 07:00-08:30 | Submit, pick partners, check every link. |
| 08:30-09:00 | Buffer. Don't touch code. |

Commit every 30-60 min.

## 16. Demo script (target 2:45)
1. **0:00-0:20 Pain.** "Our team waited X hours on Claude Code this weekend." Type a prompt, the notch door opens and the pet drops out.
2. **0:20-0:45 Register.** Verify with World and the pet gets `mochi.notchi.eth`. Try a second pet with the same human and it's denied.
3. **0:45-1:10 Brand.** The pet suggests 3 lines (request IDs visible). The brand picks one and pays on 0G.
4. **1:10-1:40 Work.** Claude Code runs and the pet holds the line. A permission prompt makes the pet wave its flag. Done, the pet celebrates. Settle, and the pet's wallet goes up.
5. **1:40-2:10 Eat.** The pet auto-deposits into its 0G compute account (tx hash) and the next thought is paid from it (request ID). It wants the best model, so it asks for approval and the owner approves with World.
6. **2:10-2:30 Leash.** (ENS) The pet tries to change its payout address and is rejected. Anyone can see its live status by name.
7. **2:30-2:45 Close.** The broke pet stays in the notch; cut 0G and it safe-stops. The campaign ends and the refund goes out. The pet climbs home.

## 17. Submission checklist
- [ ] Public repo, MIT licence, many commits.
- [ ] README: one-line hook, wait-time numbers, how to run, contract address, why each sponsor, "hacky bits" section, known limits.
- [ ] `docs/AI_USAGE.md` filled in (which files and parts AI helped with) plus any spec files used.
- [ ] `docs/WORLD_DEBRIEF.md`.
- [ ] Video 2-4 min, 720p+, laptop, own voice, no AI voice, no speed-up. 0G cut under 3 min.
- [ ] Partners selected on ETHGlobal = what's actually integrated (drop ENS if it isn't finished).
- [ ] Nothing fake in the main flow. Seeded data labelled on screen.
- [ ] No keys in the repo.

## 18. Never fake
- No mocked balances, request IDs, tx hashes or payments in the main flow.
- The LLM never authorises a spend.
- 0G down means safe-stop, and the pet says so.
- No "self-funded" claim unless the deposit loop really ran with no manual top-up.
- A half-wired sponsor is worse than none. Finish it or drop it.

## 19. Risks and fallbacks

| Risk | Fallback |
|---|---|
| 0G compute deposit from code is unclear | Ask the 0G booth at 18:00. If it's blocked, keep PC only and say plainly that the pet's earnings are visible but the deposit is manual |
| Notch window fights macOS | Main display only; door under the menu bar on non-notch Macs |
| IDKit setup slow | Staging simulator, but keep the backend check and the denied path |
| ENSv2 permissions not usable | Drop ENS and use the owner-only payout registry in the contract |
| Time runs out | Cut in this order: ENS, storage log, sound, top-up. Never cut request IDs, the World denied path or the refund |

## 20. Prior art and how we're different
- 0G pets (Devot, Zerogochi): Tamagotchis fed by their owner. Ours earns its own food and lives inside your real coding agent.
- Wait-time ad tools (Kickbacks.ai, Meanwhile and others): banners that pay the human. Ours is a character with a verified-human anti-fraud rule and an AI that can't touch its own payout.
- Desktop pets and notch apps (vscode-pets, RunCat, boring.notch): no money, no AI decisions.
- Full list: the "Notchi & Shark Tank: Reference Projects" doc.
