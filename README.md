# Gremlo

**Your agent makes you wait. Gremlo makes the wait pay.**

Gremlo is a tiny desktop pet that lives behind a door in your MacBook notch. It reacts live to Claude Code: it drops
out when the agent starts working, knocks when the agent needs your approval (you can answer from the notch), and
celebrates when the run is done. While the agent works, it holds up one short sponsored line. Brands pay per verified
view, the views are settled to the pet on NEAR testnet, and a share of every settlement goes into the pet's compute
budget, which its AI calls are charged against. One human, one pet, checked with World ID.

Prior art: sk-ruban/notchi is an open-source notch companion for Claude Code. Gremlo differs by its sponsored-impression economy, onchain settlement and a compute budget the pet pays its own thinking from.

Originally built from scratch at ETHGlobal Mumbai 2026 as **Notchi**, and renamed Gremlo for 1.0 (sk-ruban/notchi
owns that name). The hackathon build is described under [History](#history).

## How it works

```
Claude Code hooks ──> Mac app (notch, menu bar, 127.0.0.1:47474)
                         │  signed views, think calls (species, stage), approvals stay local
                         v
                      Server (Node) ──> NEAR AI Cloud: private inference in a TEE, a completion id per call
                         │          ──> World ID: one human, one pet (proof checked on the server)
                         │          ──> Vault on NEAR testnet (contracts-near): campaigns, settlements,
                         │              the pet's compute budget, one charge per AI call with its completion id
                         ^
                      Web app (Next.js): get your pet, your pet, fund a campaign, park, gallery, money
```

1. **Get a pet.** On `/pet` you connect a NEAR wallet and prove you are a person with World ID. The server checks the
   proof and registers the pet in the vault with your payout account.
2. **A brand funds a campaign.** On `/brand` the brand writes up to four lines of 6 to 40 characters (or picks from
   hooks NEAR AI writes, each with its completion id) and pays into the vault from its own wallet.
3. **The pet holds the line while your agent works.** A view counts only when the sign has been on screen for 5
   seconds, the screen is unlocked, not shared and not recorded, and someone used the Mac in the last 5 minutes; at most
   12 lines an hour. Views count only from a Mac paired to the pet (one wallet signature on `/pair`): each is a report
   signed by its Secure Enclave and appended to the campaign's public log; `gremlo verify <campaign>` replays it
   against the bill.
4. **Settlement feeds the pet.** The server settles views in the vault: most goes to the payout account, a share goes
   into the pet's compute budget. Each NEAR AI call is charged a fixed per-tier rate in NEAR against that budget, with
   the TEE-signed completion id in the log. The operator holds the NEAR AI credits; the pet can't buy credits directly
   yet. Mood follows the real budget: thriving, stable, hungry, or asleep (no paid calls).

## Quickstart

Needs macOS 13+ with Swift 5.9+, Node 22 (the version CI uses), and Rust only for the contracts. Steps 1 and 2 were
checked from a fresh clone in `/tmp` on 2026-11-13. Step 3 needs your own keys and wasn't part of that check.

```bash
# 1. clone
git clone https://github.com/DiveshK007/GREMLO.git && cd GREMLO

# 2. build and test everything (no keys needed)
(cd apps/mac && swift build && swift test)                     # Mac app + GremloCore: 92 tests
(cd apps/server && npm ci && npm test)                         # 75 tests
(cd packages/brain && npm test)                                # 16 tests, no dependencies
(cd apps/web && npm ci && npm run typecheck && npm run build && npm test)   # 4 tests (Node 22; on Node 20 use npx tsx --test lib/*.test.ts)
(cd contracts-near && cargo test)                              # vault: 3 unit + 18 integration tests
(cd contracts-accounts && cargo test)                          # factory and purse: 14 tests

# 3. run it (needs keys)
cp apps/server/.env.example apps/server/.env    # fill in: NEAR operator account and key, vault id, NEAR AI key, World app id
cp apps/web/.env.example apps/web/.env          # fill in: server URL, vault id, World app id
(cd apps/server && npm start)                   # :8787
(cd apps/web && npm run dev)                    # :3000
(cd apps/mac && swift run Gremlo)               # then menu bar → Settings → General → Claude Code → Connect
```

Every env var name is listed in [HANDOFF.md](HANDOFF.md). Values live only in your own `.env` files.

## What's real

### Live on testnet
| Claim | Proof |
|---|---|
| The vault is deployed and initialised as `vault.gremlo.testnet`, with `operator.gremlo.testnet` as operator; its code hash matches a local build of `contracts-near` | [PROOF.md, final run](PROOF.md#final-run-accounts-gremlotestnet) · deploy tx [`12bj3uDk…J4bq`](https://testnet.nearblocks.io/txns/12bj3uDkB6ufrMmKS7m4s85xma9CC1zhgevS7eMbJ4bq) |
| The full loop ran end to end: pet registered after the World ID check, verified, campaign funded, views settled, the compute budget refilled, NEAR AI calls charged against it with their completion ids | [PROOF.md, the loop (dry run, 12 Nov 2026)](PROOF.md#the-loop-dry-run-12-nov-2026), on the pre-rename `*.notchi.testnet` accounts |
| A NEAR AI completion is signed by the attested TEE that served it (`npm run verify` in `apps/server`) | [PROOF.md, NEAR AI Cloud](PROOF.md#near-ai-cloud-private-inference-in-a-tee) |

### Built, simulator only
| Claim | Evidence |
|---|---|
| iPhone app with Live Activity, widgets and lock-screen approvals; Watch app and complication | `apps/ios`; build, install and launch in the iOS and watchOS 27.2 simulators ([PLAN_1.0](docs/PLAN_1.0.md), M11). Signing, push and TestFlight need an Apple Developer account |

### Built, not deployed
| Claim | Evidence |
|---|---|
| The pet's purse: a factory and a purse contract, with a Mac key limited to `pay_inference` and per-call and daily caps. The app side is wired: a pet with a purse pays for each thought from its own account, signed on the Mac, and the server counts a payment only once the chain shows it | `contracts-accounts` (14 tests), `apps/server/src/purse.ts` (tested), `GremloCore/Near.swift` (byte-identical to near-api-js). Not deployed; setup steps in [contracts-accounts/README.md](contracts-accounts/README.md). Pets without a purse use the vault's compute budget |

### Known limits
- The final clean loop on the `*.gremlo.testnet` accounts hasn't run yet; the loop proof above is the dry run.
- Not self-funded beyond the wording above: AI calls are charged against the pet's budget (or paid from its purse, once deployed) at a fixed per-tier rate, not the real USD bill, and the operator holds the NEAR AI credits.
- The platform fee isn't published, so it shows as `—`.
- A system Focus can't be read without an Apple entitlement, and browser screen sharing isn't detected (mic and Zoom/system recording are).
- Shortcuts lists the App Intents only from an Xcode-built bundle; `gremlo://` links and the `gremlo` CLI work now.
- Community species can't be installed from the gallery yet.
- The pet page shows the species and stage only after the Mac has thought once.
- The redesigned menu bar, Settings and web pages haven't been watched running yet.
- Windows and Linux aren't built.

## Repo

| Part | Where |
|---|---|
| Mac app: eight species, the plate, Notch Live and approvals, growth and the Closet, bug hunt, git moods, room, focus, privacy rules, stream mode, postcard, team and park | `apps/mac` (rules and tests in `GremloCore`) |
| `gremlo` CLI, `gremlo://` links, Shortcuts | `apps/mac/Sources/GremloCLI` |
| Server: campaigns, signed sightings with a public log, A/B, moments, reports, park, relay, gallery, phone mailbox | `apps/server` |
| NEAR AI calls, mood to model, claim checks | `packages/brain` |
| Web: the site at `/` and the app pages | `apps/web` |
| iPhone, Watch | `apps/ios` |
| VS Code and Cursor extension, Raycast extension | `apps/vscode`, `apps/raycast` |
| Vault (campaigns, compute budget) | `contracts-near` |
| Factory and purse (not deployed) | `contracts-accounts` |

Design source: `docs/design/1.0/`. Build plan and open items: `docs/PLAN_1.0.md`. Handoff: `HANDOFF.md`.

## History

The ETHGlobal Mumbai 2026 build, as written at the time. It ran on a different stack and is kept on the
`ethglobal-0g` branch; nothing below describes `main`.

> On one laptop, during this hackathon, we spent 1.6 hours waiting on Claude Code (1,589 agent events), measured by Gremlo's own hook log.
### What it does

1. **A developer gets a pet.** They prove they are a unique human with World ID. One person, one pet, so brands only pay real screens. The pet is registered onchain with a payout address only the owner can change.
2. **A brand funds a campaign.** The brand picks a tone (bold, calm or dev-meme) and Gremlo writes three hooks of up to 40 characters on 0G Private Computer (each shows its request ID). The brand picks one and pays into the `CampaignVault` contract on 0G Galileo. Unspent budget is refunded when the campaign ends.
3. **The pet works.** Claude Code hooks tell the pet what the agent is doing: working, waiting for permission, idle, done, failed. While the agent works, the pet holds the brand's line. Each event asks the pet's 0G brain what to do next.
4. **The pet gets paid.** Impressions are settled onchain to the pet's payout address. The pet's mood comes from its real balance: thriving, stable, hungry or asleep.

### Proof it is real

| What | Where |
|---|---|
| CampaignVault (verified) | [0xe74a2dd7C3acFdf7180e43cB41644EA386f9B7DB](https://chainscan-galileo.0g.ai/address/0xe74a2dd7C3acFdf7180e43cB41644EA386f9B7DB) on 0G Galileo (16602) |
| Pet registered after a real World ID proof | [0x24340bcc...52148f3](https://chainscan-galileo.0g.ai/tx/0x24340bccc045b7ca596aaf05e32e8331445ca82b77721f755a3a47e1e52148f3) |
| Brand campaign funded | [0x655415b2...a370f30](https://chainscan-galileo.0g.ai/tx/0x655415b2eb9b5de7fe80d53849713227f53ed19440b009248400d318ba370f30) |
| Ad lines written on 0G | request `ecbcab9c-96ee-4dc0-880d-e3622419f7d7` |
| Pet decision on 0G | request `61eeed8e-7f32-4317-bcf5-e573d35553a2` |
| Campaign #2 funded | [0x208f143c...aba26d5](https://chainscan-galileo.0g.ai/tx/0x208f143c6b049278d851d912a6de8b937936af27cee1fd93a5ec906caaba26d5) |
| Impressions settled to the pet | [0x45cf8fed...ab651704](https://chainscan-galileo.0g.ai/tx/0x45cf8fed373b3fc9db171297a7f96df4b649996c06de325f4be16be9ab651704) |

### The pet

- **Hidden door.** The notch looks like stock hardware. The door only appears while the pet crosses it: it fades in, glows, swings open, closes and fades out.
- **Ticker sign.** While the agent works the pet walks slowly holding the sponsored line. Lines that don't fit scroll like a news ticker and pause when your cursor is on the pet.
- **Walks every edge.** It walks the bottom, climbs the side wall and walks the top edge upside down on its way home. The sign and bubbles stay upright.
- **Three avatars.** Gremlo, Gremlo Ink and Gremlo Signal, switched live from the menu-bar popover.
- **Settings.** Sounds, sponsored lines on/off, ticker, walk speed, how long before it goes home, and a "Send pet home" button.
- **Reminders.** After the agent stops or asks for approval, Gremlo reminds you every 2, 5 or 10 minutes (or never) until your next prompt.
- **Stays out of full-screen apps.** The pet shows on every normal desktop but never covers full-screen apps; a setting shows it there too. Impressions only count while the sign is actually on screen.
- **Reacts to you.** Hover and it turns to smile; click it repeatedly and it gets annoyed, then calms down after 6 seconds. It never interrupts work, approvals or what its 0G brain says.

### What counts as a paid view

A view is paid only when all of these hold, measured on the Mac and sent inside the device-signed request:

- the sign was on screen for at least 5 seconds;
- the screen was unlocked;
- the sign's window was visible (not on another Space, not behind a full-screen app);
- someone used the keyboard or mouse in the last 5 minutes.

The server refuses views that break a rule and says which one. At most one view per campaign per minute and 120 a day per pet. Views then wait out the holdback and the fraud rules before they are paid.

### How each sponsor is used

**0G (Private Computer).** The pet's brain. Every pet decision and every set of ad lines is an inference call on 0G Private Computer (TEE routing), and the request ID is shown in the UI. We use 0G's own `0gm-1.0-35b-a3b` for everyday decisions and `glm-5.3` when the pet is thriving or writing ad lines. If 0G can't be reached, the pet goes to sleep and says why. It never invents a decision. The campaign contract also lives on 0G Galileo.

**World (World ID).** One human, one pet. Ad networks die from fake views, so a pet only gets registered (and paid) after a World ID proof. The proof is checked on our server against the World Developer Portal, the nullifier is stored, and a second pet from the same person is refused with "You already have a pet."

### Architecture

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

### Tests

- Contracts: 20 Foundry tests including fuzzing (`forge test`). The fuzz test checks the pet's earnings plus what's left always equal the budget.
- Server: 24 tests (`npm test` in `apps/server`).
- Brain: 6 tests (`npm test` in `packages/brain`).

### Run it

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

### Hacky bits (what was hard)

- **Wallets can't estimate gas on 0G Galileo.** Core showed "pre-execution unavailable" and transactions reverted with no reason. We set the gas limit explicitly in the web app.
- **World ID v4 vs legacy proofs.** IDKit returned the legacy proof shape when legacy proofs were allowed, but the v4 verify endpoint only accepts v4 results. We request v4 proofs and let the portal's verify response decide, reading the nullifier from the field each version binds (so a client can't inject its own nullifier).
- **Claude Code hooks must never slow the agent.** Every hook is a `curl -m 1 ... || true` to localhost. A closed pet app never blocks or changes Claude Code, and hooks never return a decision. The local log keeps only metadata (time, event, session, tool), never prompts or file contents.
- **Notch geometry.** The door position comes from `NSScreen.safeAreaInsets` and the auxiliary top areas. Macs without a notch get the door under the menu bar.
- **Honest moods.** The mood is read from the pet's real onchain balance, cached for 30s. If the RPC fails, the pet is "asleep: can't read balance" rather than guessing.

### Known limits

- Impressions are reported by the client in v1. World ID's one-human-one-pet rule and a one-per-minute limit per pet per campaign (checked on the server) are the defence. Reports are not signed yet.
- The pet does not yet top up its own 0G compute account from its earnings. Its 0G calls are paid from the team's account. Next step: the pet's wallet deposits into its own 0G Router balance.
- The World flow was tested with World ID staging.
- ENS: we started giving each pet an ENS subname for its public status and payout; Sepolia moved .eth registration to ENSv2 during the hackathon, so this ships next.

## AI usage

See [docs/AI_USAGE.md](docs/AI_USAGE.md).
