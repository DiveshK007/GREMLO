# Notchi

**Your coding agent makes you wait. Notchi makes that wait pay for itself.**

Notchi is a tiny desktop pet that lives behind a door in your MacBook notch. When Claude Code starts working, the door opens, the pet drops out and holds up one short sponsored line while the agent thinks. Brands pay per real impression. The pet's brain runs on 0G, and every decision it makes has a 0G request ID.

Built from scratch at ETHGlobal Mumbai 2026.

## Notchi 1.0 (branch `notchi-1.0`)

1.0 implements the design export in `docs/design/1.0/`. Milestones and what is still open: `docs/PLAN_1.0.md`.
The sections below this one describe the earlier hackathon builds.

| Part | Where | Build and test |
|---|---|---|
| Mac app: eight species, the plate, Notch Live, approvals from the notch, growth and the Closet, bug hunt, git moods, room, focus, privacy rules, stream mode, postcard, team and park | `apps/mac` | `swift build && swift test` (NotchiCore holds the rules; 86 tests) |
| `notchi` CLI, `notchi://` links, Shortcuts | `apps/mac/Sources/NotchiCLI` | `swift run NotchiCLI --help` |
| Server: campaigns, signed sightings with a public log, A/B, moments, reports, park, relay, gallery, phone mailbox | `apps/server` | `npm test` |
| Web: the 1.0 site at `/`, get your pet, your pet, brand console, park, gallery, money | `apps/web` | `npm test`; build in a copy |
| VS Code and Cursor extension | `apps/vscode` | `npm run compile` |
| Raycast extension | `apps/raycast` | `npm run dev` |
| iPhone, Live Activity, widgets, Watch and complication | `apps/ios` | `xcodegen generate`, then build for the simulator |
| Vault (campaigns, compute budget) | `contracts-near` | `cargo test` |
| Readable pet accounts: factory and purse (optional, not deployed) | `contracts-accounts` | `./build.sh && cargo test` |

`notchi verify <campaign>` replays a campaign's public log: every counted sighting must be a signed report from a
paired Mac, the hash chain must be unbroken, and the total must match the bill.

> On one laptop, during this hackathon, we spent 1.6 hours waiting on Claude Code (1,589 agent events), measured by Notchi's own hook log.

## What it does

1. **A developer gets a pet.** They prove they are a unique human with World ID. One person, one pet, so brands only pay real screens. The pet is registered onchain with a payout address only the owner can change.
2. **A brand funds a campaign.** The brand picks a tone (bold, calm or dev-meme) and Notchi writes three hooks of up to 40 characters on 0G Private Computer (each shows its request ID). The brand picks one and pays into the `CampaignVault` contract on 0G Galileo. Unspent budget is refunded when the campaign ends.
3. **The pet works.** Claude Code hooks tell the pet what the agent is doing: working, waiting for permission, idle, done, failed. While the agent works, the pet holds the brand's line. Each event asks the pet's 0G brain what to do next.
4. **The pet gets paid.** Impressions are settled onchain to the pet's payout address. The pet's mood comes from its real balance: thriving, stable, hungry or asleep.

## Proof it is real

| What | Where |
|---|---|
| CampaignVault (verified) | [0xe74a2dd7C3acFdf7180e43cB41644EA386f9B7DB](https://chainscan-galileo.0g.ai/address/0xe74a2dd7C3acFdf7180e43cB41644EA386f9B7DB) on 0G Galileo (16602) |
| Pet registered after a real World ID proof | [0x24340bcc...52148f3](https://chainscan-galileo.0g.ai/tx/0x24340bccc045b7ca596aaf05e32e8331445ca82b77721f755a3a47e1e52148f3) |
| Brand campaign funded | [0x655415b2...a370f30](https://chainscan-galileo.0g.ai/tx/0x655415b2eb9b5de7fe80d53849713227f53ed19440b009248400d318ba370f30) |
| Ad lines written on 0G | request `ecbcab9c-96ee-4dc0-880d-e3622419f7d7` |
| Pet decision on 0G | request `61eeed8e-7f32-4317-bcf5-e573d35553a2` |
| Campaign #2 funded | [0x208f143c...aba26d5](https://chainscan-galileo.0g.ai/tx/0x208f143c6b049278d851d912a6de8b937936af27cee1fd93a5ec906caaba26d5) |
| Impressions settled to the pet | [0x45cf8fed...ab651704](https://chainscan-galileo.0g.ai/tx/0x45cf8fed373b3fc9db171297a7f96df4b649996c06de325f4be16be9ab651704) |

## The pet

- **Hidden door.** The notch looks like stock hardware. The door only appears while the pet crosses it: it fades in, glows, swings open, closes and fades out.
- **Ticker sign.** While the agent works the pet walks slowly holding the sponsored line. Lines that don't fit scroll like a news ticker and pause when your cursor is on the pet.
- **Walks every edge.** It walks the bottom, climbs the side wall and walks the top edge upside down on its way home. The sign and bubbles stay upright.
- **Three avatars.** Notchi, Notchi Ink and Notchi Signal, switched live from the menu-bar popover.
- **Settings.** Sounds, sponsored lines on/off, ticker, walk speed, how long before it goes home, and a "Send pet home" button.
- **Reminders.** After the agent stops or asks for approval, Notchi reminds you every 2, 5 or 10 minutes (or never) until your next prompt.
- **Stays out of full-screen apps.** The pet shows on every normal desktop but never covers full-screen apps; a setting shows it there too. Impressions only count while the sign is actually on screen.
- **Reacts to you.** Hover and it turns to smile; click it repeatedly and it gets annoyed, then calms down after 6 seconds. It never interrupts work, approvals or what its 0G brain says.

## What counts as a paid view

A view is paid only when all of these hold, measured on the Mac and sent inside the device-signed request:

- the sign was on screen for at least 5 seconds;
- the screen was unlocked;
- the sign's window was visible (not on another Space, not behind a full-screen app);
- someone used the keyboard or mouse in the last 5 minutes.

The server refuses views that break a rule and says which one. At most one view per campaign per minute and 120 a day per pet. Views then wait out the holdback and the fraud rules before they are paid.

## How each sponsor is used

**0G (Private Computer).** The pet's brain. Every pet decision and every set of ad lines is an inference call on 0G Private Computer (TEE routing), and the request ID is shown in the UI. We use 0G's own `0gm-1.0-35b-a3b` for everyday decisions and `glm-5.3` when the pet is thriving or writing ad lines. If 0G can't be reached, the pet goes to sleep and says why. It never invents a decision. The campaign contract also lives on 0G Galileo.

**World (World ID).** One human, one pet. Ad networks die from fake views, so a pet only gets registered (and paid) after a World ID proof. The proof is checked on our server against the World Developer Portal, the nullifier is stored, and a second pet from the same person is refused with "You already have a pet."

## Architecture

```
Claude Code hooks ──> Mac app (Swift, notch window, hook server on 127.0.0.1:47474)
                          │  GET /campaigns/active, GET /pets/:name, POST /pets/:name/think
                          v
                     Server (Node/TS) ──> 0G Private Computer (inference, request IDs)
                          │           ──> World Developer Portal (proof verify)
                          │           ──> CampaignVault on 0G Galileo (register, settle)
                          ^
                     Web app (Next.js): /pet (World ID) and /brand (fund, refund)
```

| Folder | What |
|---|---|
| `apps/mac` | Notch overlay, door, sprites, state machine, menu-bar popover, hook server |
| `apps/server` | Campaigns, impressions, settlement, World verify, think route |
| `apps/web` | Pet registration and brand checkout |
| `packages/brain` | 0G calls, mood to model, safe-stop |
| `contracts` | `CampaignVault.sol`, Foundry tests, deploy script |

## Tests

- Contracts: 20 Foundry tests including fuzzing (`forge test`). The fuzz test checks the pet's earnings plus what's left always equal the budget.
- Server: 24 tests (`npm test` in `apps/server`).
- Brain: 6 tests (`npm test` in `packages/brain`).

## Run it

```bash
# 1. contracts (already deployed; only to redeploy)
cd contracts && forge test

# 2. server
cd apps/server && cp .env.example .env   # fill in keys
npm install && npm start                 # :8787

# 3. web
cd apps/web && cp .env.example .env.local
npm install && npm run dev               # :3000

# 4. Mac app
cd apps/mac && swift run

# 5. hooks: merge pet-hooks.user-settings.json into ~/.claude/settings.json
```

## Hacky bits (what was hard)

- **Wallets can't estimate gas on 0G Galileo.** Core showed "pre-execution unavailable" and transactions reverted with no reason. We set the gas limit explicitly in the web app.
- **World ID v4 vs legacy proofs.** IDKit returned the legacy proof shape when legacy proofs were allowed, but the v4 verify endpoint only accepts v4 results. We request v4 proofs and let the portal's verify response decide, reading the nullifier from the field each version binds (so a client can't inject its own nullifier).
- **Claude Code hooks must never slow the agent.** Every hook is a `curl -m 1 ... || true` to localhost. A closed pet app never blocks or changes Claude Code, and hooks never return a decision. The local log keeps only metadata (time, event, session, tool), never prompts or file contents.
- **Notch geometry.** The door position comes from `NSScreen.safeAreaInsets` and the auxiliary top areas. Macs without a notch get the door under the menu bar.
- **Honest moods.** The mood is read from the pet's real onchain balance, cached for 30s. If the RPC fails, the pet is "asleep: can't read balance" rather than guessing.

## Known limits

- Impressions are reported by the client in v1. World ID's one-human-one-pet rule and a one-per-minute limit per pet per campaign (checked on the server) are the defence. Reports are not signed yet.
- The pet does not yet top up its own 0G compute account from its earnings. Its 0G calls are paid from the team's account. Next step: the pet's wallet deposits into its own 0G Router balance.
- The World flow was tested with World ID staging.
- ENS: we started giving each pet an ENS subname for its public status and payout; Sepolia moved .eth registration to ENSv2 during the hackathon, so this ships next.

## AI usage

See [docs/AI_USAGE.md](docs/AI_USAGE.md).
