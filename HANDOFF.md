# Handoff

Gremlo: a Mac pet in the notch that reacts to Claude Code, holds a sponsored line while the agent works, and
pays for its own thinking from what it earns. Formerly Notchi (renamed for 1.0; sk-ruban/notchi owns that name).

Repo: https://github.com/DiveshK007/GREMLO, local clone `~/GREMLO`. The old `~/notchi` folder and its worktrees
point at the old Notchi repo and are no longer the place to work.

## Branches

| Branch | What it is |
|---|---|
| `main` (default) | Gremlo 1.0: everything below. Work here. |
| `ethglobal-0g` | The ETHGlobal Mumbai 2026 build (0G), kept as history |
| `near` | The NEAR port that 1.0 is built on, kept as history |
| `v2`, `chain`, `mac`, `server`, `web` | Older working branches, kept as history |

CI (`.github/workflows/ci.yml`) runs on every push and pull request: contracts, contracts-near,
contracts-accounts, server, brain, web, mac (build, tests, release script) and the API image. It is green on `main`.

## Done

- 1.0 milestones M0-M13 from `docs/PLAN_1.0.md`: the Mac app (eight species, plate, Notch Live and approvals
  with guards, growth and Closet, bug hunt, git moods, room, focus, privacy rules, stream mode, postcard, team
  relay, park, phone link), the `gremlo` CLI and socket, `gremlo://` links, Shortcuts, Raycast, VS Code/Cursor,
  the server (signed sightings with a public log and `gremlo verify`, A/B, moments, reports, gallery, phone
  mailbox), the web (1.0 site at `/`, park, gallery, money page, brand console), iPhone and Watch (simulator),
  the factory and purse contracts (not deployed).
- Two code-review passes; 20 findings fixed (incl. a settlement that could be paid twice).
- Rename to Gremlo with a one-time migration for existing installs (`apps/mac/Sources/GremloCore/Legacy.swift`
  lists every old name; `Migrate+Mac.swift` runs it).
- Final-run accounts created and the vault deployed on them (PROOF.md, final-run section).

## Left

- On-screen check of the Mac app (nothing in 1.0 has been watched running yet).
- The final clean loop on the gremlo accounts, filling PROOF.md's final-run rows.
- Known limits, not bugs: system Focus can't be read without an Apple entitlement; browser screen sharing
  isn't detected; companions take agent windows front to back (the exact agent window isn't knowable);
  Shortcuts lists the App Intents only from an Xcode-built bundle (`gremlo://` and the CLI work now).
- Not done on purpose: the purse contracts aren't deployed; the Fly app and volume keep their `notchi` names.
- Open items per milestone: `docs/PLAN_1.0.md`.

## Accounts (NEAR testnet)

Final run (set through env only; no account id is hard-coded in code):

| Account | Role |
|---|---|
| `gremlo.testnet` | vault admin |
| `vault.gremlo.testnet` | vault contract (deployed, tx in PROOF.md) |
| `operator.gremlo.testnet` | operator: registers pets, settles views, charges compute |
| `owner.gremlo.testnet` | pet owner |
| `byte.gremlo.testnet` | pet payout |

Dry run (before the rename, kept under their original names): `notchi.testnet`, `vault.notchi.testnet`,
`operator.notchi.testnet`, `brand.notchi.testnet`, `mochi.notchi.testnet`.

## Env var names (values live only in each person's own `.env`)

- Server (`apps/server/.env`): `NEAR_NETWORK`, `NEAR_CONTRACT_ID`, `NEAR_RPC_URL`, `NEAR_OPERATOR_ACCOUNT_ID`,
  `NEAR_OPERATOR_PRIVATE_KEY`, `PORT`, `HOST`, `REQUIRE_SIGNED`, `TRUST_PROXY`, `WORLD_APP_ID`, `RP_ID`,
  `RP_SIGNING_KEY`, `WORLD_API_BASE` (local sandbox only), `NEAR_AI_BASE_URL`, `NEAR_AI_API_KEY`,
  `NEAR_AI_MODEL_SMART`, `NEAR_AI_MODEL_CHEAP`, `COMPUTE_FEE_SMART_YOCTO`, `COMPUTE_FEE_CHEAP_YOCTO`,
  `STORE_PATH`, `LOG_DIR`, `GALLERY_DIR`, `GALLERY_REVIEW_TOKEN`, `WEB_ORIGIN`, `WORKER`, `WORKER_MINUTES`,
  `HOLDBACK_HOURS`, `TRY_DAILY_CAP`, `MAIL_FROM`, `RESEND_API_KEY`, `ARKIV`, `ARKIV_KEY`, `ARKIV_ACCESS_KEY`
- Web (`apps/web/.env`): `NEXT_PUBLIC_SERVER_URL`, `NEXT_PUBLIC_WEB_URL`, `NEXT_PUBLIC_NEAR_NETWORK`,
  `NEXT_PUBLIC_NEAR_CONTRACT_ID`, `NEXT_PUBLIC_NEAR_RPC_URL`, `NEXT_PUBLIC_WORLD_APP_ID`,
  `NEXT_PUBLIC_WORLD_RP_ID`, `NEXT_PUBLIC_WORLD_PRESET`, `NEXT_PUBLIC_WORLD_ENV`
- Mac app and CLI: `GREMLO_SERVER`, `GREMLO_WEB`, `GREMLO_PET`, `GREMLO_SKIN`, `GREMLO_HOME_AFTER`,
  `GREMLO_RECORD` (tests), `GREMLO_GIT_SINK` (tests). The old `NOTCHI_*` names are read as a fallback for one release.

The `.env` files are not in git and were not copied into `~/GREMLO`; each person copies their own.

## Rules (for people and for AI assistants)

- Never create, copy, move, read or delete any `.env` file. Only edit the `.env.example` files.
- Never read, list or open `~/.near-credentials`, `*.pem`, `*.key` or anything holding a private key. Never print keys.
  Checking the near CLI means `--help` and `--version` only.
- Never start or restart the server, web app or Mac app, in the background or otherwise. The owner runs them in
  their own tabs; say the exact command instead.
- Never run `next build` in `apps/web` while the dev server may be running. Build in a copy under `/tmp`.
  Build and test the Mac package in a `/tmp` copy too (`swift build && swift test`).
- Never invent numbers, tx hashes, request IDs or claims. Proof comes from real runs the owner does.
- One committer. Small commits with real messages; no single dump. Commit and push after each piece of work.
- Product copy names no chain ("purse", "earned", "paid for thinking"); account ids and hashes only in Advanced
  views, docs and the README. More in `CLAUDE.md`.

## Next steps

1. **On-screen smoke test.** Copy your `.env` files into `~/GREMLO`, `npm install` in `apps/server`,
   `apps/web` and `packages/brain`, then in your own tabs: the server (`cd apps/server && npm start`), the web
   (`cd apps/web && npm run dev`), the Mac app (`cd apps/mac && swift run Gremlo`). Check: connect Claude Code
   (Settings), the notch states and an approval (allow, deny, a risky command needing a click), hatching, a
   failing then passing test (bugs), the room (two-finger pull down on the notch), a screen share hiding the
   pets, the Settings sections, and the site at `/` in light and dark.
2. **The final clean loop** on the gremlo accounts, no manual top-up: register the pet (owner
   `owner.gremlo.testnet`, payout `byte.gremlo.testnet`) with World ID, pair the Mac, fund a campaign, let the pet
   hold the line while an agent works, settle, see the compute budget refill and the next thought paid from it,
   then `gremlo verify <campaign>`. Fill PROOF.md's final-run rows from that run.
