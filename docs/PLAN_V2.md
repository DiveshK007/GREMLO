# Gremlo v2: implementation plan

Status: plan only. Work happens on branch `v2` (never commit to `main` directly; merge by PR once CI is green).
Scope: everything discussed after the ETHGlobal build: the production analysis, the v2 product plan (hook engine, success states, homepage, Arkiv, deploy, quality, retention), and the risks found while building and recording.

---

## 0. Where we start (honest baseline)

| Area | Works today | Gap that matters for v2 |
|---|---|---|
| `contracts/CampaignVault.sol` | create, settle (verified pets only), refund after end + 1h grace, 20 Foundry tests incl. fuzz | testnet only, single hot operator key, native token only, one tx per pet per settle, no pause, no audit |
| `apps/server` | register (World proof, nullifier), impressions (1/min/pet/campaign), settle with plain errors, lines (tone), think, active campaign | JSON file store, one process, no auth (safe only on 127.0.0.1), settle is a manual button, unsigned impressions |
| `packages/brain` | 0G calls with real request IDs, safe-stop, mood to model, tone, token limits fixed | no claim validation, no hook formats, pet never deposits into its own 0G compute account |
| `apps/web` | v2 look, /pet World flow (incl. denied path), /brand hooks with tone, fund, settle, refund | no success screen, uneven loading/error states, no dashboard, no live stats, homepage static |
| `apps/mac` | notch door, walks, ticker, avatars, settings, reminders, cursor play, impressions after 5 s on screen | not notarised, no auto-update, hooks installed by hand, pet chosen by env var, macOS only, sign not clickable |
| World | staging simulator, nullifier stored, denied path works | proof not bound to owner wallet, no production preset |
| ENS | not shipped | Sepolia moved .eth registration to ENSv2 |

Rule that carries over from v1: never fake balances, request IDs, tx hashes, views or clicks. Seeded data is labelled. A dash means unknown.

---

## 1. Principles for v2

1. **Useful first, sponsored second.** The pet is wanted without ads (agent status, approvals, done nudges). Sponsored lines are opt-in.
2. **Verification is the moat.** Every view and click is signed, rate-limited, tied to one verified human and auditable.
3. **Deterministic checks guard money and claims.** The LLM never authorises a payment and never gets the last word on what a brand may claim.
4. **Crypto under the hood.** Brands should be able to pay by card; developers receive stablecoins; chain is the audit trail.
5. **Small, tested steps.** Each step lands with its tests and passes CI before the next.

---

## 2. Phase order and why it differs from the draft

| # | Phase | Why here |
|---|---|---|
| A | Foundations: CI, store module, signed requests, settlement worker | Every later phase writes data (hooks, clicks, streaks) and needs auth before anything goes public |
| B | Hook engine (draft phase 1) + claim validator + clickable sign | The core product upgrade |
| C | No silent success + brand dashboard v1 (draft phase 2) | Brands need to see what they bought |
| D | Homepage v2 (draft phase 3) | Needs real stats from A/B/C to show |
| E | Trust and money hardening | Before real money: signed views/clicks, fraud rules, contract v2, pet self-funding |
| F | Retention: developers and brands | Needs earnings/click data from B–E |
| G | Deploy and distribution (draft phase 5) | Public only once A and E are done |
| H | Arkiv (draft phase 4) | Optional, public-by-design data only |
| I | Scale: more agents, Windows/Linux, teams, card payments, legal, ENS | After product-market signal |

Quality (draft phase 6) is not a phase: CI starts in A and every phase adds its tests; Playwright and Sentry land in C and G.

Estimates are working days for one experienced developer with Claude Code; parallelise web/server/mac where noted.

---

## Phase A: foundations (5–7 days)

**A1. CI (1 day)**
- `.github/workflows/ci.yml`: jobs for `forge test`, `apps/server npm test`, `packages/brain npm test`, `apps/web` typecheck + `next build`, `apps/mac swift build` (macos runner). Cache deps.
- Branch protection on `main`: CI green + one review.

**A2. Store module, then Postgres (2 days)**
- Introduce `apps/server/src/db.ts` with the operations the server already uses (pets, nullifiers, pending, lines, brands, today, thoughts, lastImpression) behind functions, keeping the JSON implementation first so behaviour does not change.
- Postgres implementation behind the same functions (`postgres` npm package, plain SQL, no ORM). Migrations in `apps/server/migrations/*.sql`.
- Schema v1:
  - `pets(id, name unique, pet_key unique, owner, payout, register_tx, created_at)`
  - `nullifiers(nullifier pk, pet_id)`
  - `campaigns(id pk = onchain id, brand_address, brand_name, rate_wei, end_time, line_hash, created_tx, created_at)`
  - `hooks(id, campaign_id, format, text, request_id, chosen bool, weight)` (used in B)
  - `impressions(id, campaign_id, pet_id, hook_id, at, signature, status: pending|settled|void, settle_tx)`
  - `clicks(id, campaign_id, pet_id, hook_id, at, signature, status)` (used in B)
  - `thoughts(pet_id, action, request_id, at)`
  - `settlements(id, campaign_id, pet_id, count, amount_wei, tx_hash, status: sent|confirmed|unconfirmed|failed, at)`
- One-off migration script from `data.json`.
- Tests: the existing server tests run against both implementations (in-memory Postgres via `pg-mem` or a CI Postgres service).

**A3. Signed requests from the Mac app (2 days)**
- Mac: per-install P-256 key in the Secure Enclave (`SecKeyCreateRandomKey` with `kSecAttrTokenIDSecureEnclave`); public key shown in the popover and registered as `pet_key`.
- Every Mac → server call carries `X-Gremlo-Key`, `X-Gremlo-Time`, `X-Gremlo-Sig` over `method + path + body hash + time`. Server verifies (P-256 via WebCrypto), rejects > 60 s skew and replays (nonce cache).
- Routes that cost money or move money (`/pets/:k/think`, `/impressions`, `/clicks`) require a valid signature from a registered pet. Brand routes require a wallet signature (SIWE) or session.
- Tests: valid, wrong key, replay, clock skew.

**A4. Automatic settlement worker (1 day)**
- A job every 10 min (and the existing button) settles pending impressions per campaign, using the existing `planSettlement` and `markSettled` logic, recording rows in `settlements`.
- Unconfirmed txs are re-checked by hash before any retry (no double pay).
- Refund keeper: after `endTime + SETTLE_GRACE`, call `close(id)` automatically so brands get unspent budget back without clicking.
- Tests: plan, unconfirmed handling, keeper timing.

**Exit criteria:** CI green on every push; server runs on Postgres locally with the same tests; Mac requests signed; settlement and refunds run without a human.

---

## Phase B: hook engine (6–8 days)

**B1. Brand inputs (web + server, 1 day)**
- `/brand` step 1 becomes a form: product, audience, offer (discount / free trial / none), proof points (one per line, brand-supplied, with a checkbox "these claims are ours and accurate"), call to action, URL (https only, validated, no redirects to other domains at submit time).
- Stored as `campaign_briefs` (private; never published).

**B2. `POST /campaigns/hooks` (brain + server, 2 days)**
- Formats: `humour, sarcasm, offer, question, bold-claim, urgency, story, dev-meme`. 0G writes 2 per format (16 total), max 80 chars, plain, no emoji.
- System prompt forbids numbers, results, comparisons or claims not present in the proof points; bold-claim and urgency may only reuse proof points/offer verbatim.
- **Deterministic claim validator** in `packages/brain/claims.js` (the part we can promise):
  - any digit, %, currency, multiplier ("10x"), time claim ("in 30 seconds") in a hook must appear in the proof points or offer, else the hook is dropped and the drop reason is returned
  - superlatives (`best, fastest, #1, only, guaranteed`) dropped unless present in proof points
  - length ≤ 80, no URLs inside the line, no emoji
- Every hook carries its 0G request ID; the UI labels lines "Sponsored" and shows "written by AI · <request id>".
- If 0G fails or every hook is dropped: show the real error and let the brand write their own (their own lines also go through the validator).
- Tests: validator table tests (allowed vs invented numbers/superlatives), prompt contains the rule, 16-hook shape, failure path.

**B3. Pick 3–5 and rotate (1 day)**
- Brand selects 3–5 hooks; `lineHash` onchain becomes the hash of the sorted hook set (contract unchanged: it already stores one bytes32).
- `GET /campaigns/active` returns `{ campaignId, hooks: [{ id, text }], url, brand }`.
- Mac rotates hooks per appearance (round robin, later weighted by B5). Impressions carry `hook_id`.
- Tests: rotation order, hash of set, mismatch rejected.

**B4. Clickable sign (Mac + server, 2 days)**
- Sign window joins the existing per-pixel hit-testing: hover highlights the sign (cursor changes), a deliberate click opens the URL. No click handling while the agent needs approval.
- The click goes through `GET /c/:campaign/:hook?pet=…&sig=…`: server verifies the signature, logs a click (dedupe: 1 per pet per campaign per 10 min), then 302s to the brand URL with `utm_source=gremlo&utm_campaign=<id>`.
- Clicks are reported to brands; they are not paid per click in v2.0 (CPM only) until click fraud rules from E are live.
- Tests: signature, dedupe, redirect target exactly the stored URL.

**B5. Auto-optimise (1 day)**
- Thompson sampling on clicks per impression per hook, with a floor: every hook gets at least 15% of views until it has 200 views, so early noise does not starve hooks.
- Brand can lock a hook to "always on" or pause one.
- Tests: deterministic seed, floor respected, paused hook never served.

**Exit criteria:** a brand creates a campaign from the brief form, gets up to 16 validated hooks with request IDs, picks 3–5, the pet rotates them, a click opens the URL through the redirect and appears in the data.

---

## Phase C: no silent success + brand dashboard v1 (4–5 days)

**C1. State audit (1 day)**
- Every web action (connect, hooks, fund, record, check, settle, close, register, World steps) has: idle, loading (with what is happening and how long it may take), success (what happened + receipt), error (what failed + what to do). One shared `<ActionState>` pattern, not per-page ad hoc.

**C2. Campaign success screen (1 day)**
- "Your campaign is live": live preview of the pet (sprite) holding the chosen hooks as a ticker, receipt tx link, budget, rate, estimated views (budget / rate, labelled estimate), end time, "Share" (copy link to a public campaign card) and "View dashboard".

**C3. Brand dashboard v1 (2 days)**
- `/brand/c/:id` (wallet-signed session): views, unique humans, clicks, CTR per hook and per format, spend vs budget, settlement txs, time left, top-up and pause buttons, refund state.
- Data from Postgres; every number links to its source (settlement tx, request ID).

**C4. Playwright e2e (1 day)**
- Runs against a local Anvil chain + deployed vault + server on test Postgres + web, with a stub 0G endpoint returning fixed hooks with fixed request IDs (test-only, never in production builds).
- Flows: register (World verify stubbed at the HTTP boundary) → fund → impressions → settle → dashboard shows the settlement tx; denied registration; insufficient balance message.
- Runs in CI.

**Exit criteria:** no action in the web app can succeed or fail silently; e2e green in CI.

---

## Phase D: homepage v2 (3–4 days)

- Hero: the animated pet (sprite sheet) walking and holding a scrolling hook. Hook text = the live campaign's current hook, or "Your line here" if none (real data only).
- "Try a hook": product field → one 0G call → the pet shows a hook. Limits: 3 per IP per hour, a global daily spend cap in the server, cache by normalized input, the claim validator applied, labelled "example, not a live campaign".
- Live stats strip from Postgres + chain: campaigns run, verified views, paid to developers (sum of confirmed settlements). Numbers update; no seeded values.
- Scroll reveals with the notch door as the section transition, developer/brand split, a 15–20 s muted demo loop from the real recording.
- Respect `prefers-reduced-motion`; LCP < 2.5 s; images and the loop lazy-loaded.

**Exit criteria:** homepage shows only real numbers, the try-it call is rate-limited and capped, Lighthouse performance ≥ 85.

---

## Phase E: trust and money hardening (8–12 days, before real money)

**E1. Signed views and clicks (2 days)**
- Impressions and clicks are signed by the Secure Enclave key (A3) and include: hook id, sign-on-screen duration, screen unlocked, not covered by a full-screen app, last user input within N minutes.
- Viewability standard published in the README and enforced by the server.

**E2. Fraud rules and holdback (2 days)**
- Rules: impossible hours, identical timing patterns, too many pets per IP range, clicks with no prior view, sudden spikes.
- Holdback: impressions settle after 24 h; flagged ones go to `void` with a reason; brands see voided counts.

**E3. World binding (1 day)**
- Signal = owner address; server checks the proof's signal hash matches `ownerAddress` (closes the replay gap from review).
- Production preset (Orb or device) behind config, staging only in dev.

**E4. Contract v2 (4–5 days + external audit)**
- `pause()` by admin multisig; operator role held by a KMS-backed signer, rotated without redeploying campaigns.
- ERC-20 budgets (USDC or another stablecoin) alongside native; rate in token units.
- Batched settle: `settleBatch(id, pets[], counts[])` in one tx, still capped by remaining budget, still verified pets only.
- Events for every state change (already true; keep).
- Foundry tests for all of the above + invariant tests (paid + remaining == budget). External audit before mainnet.

**E5. The pet pays for its own brain (2 days)**
- `brain.autoDeposit()`: when the pet's payout wallet is above a threshold, deposit into its own 0G compute account, up to a daily spend cap set by the owner.
- Above the cap: an approval request; the owner approves with a World proof (the v1 brief's approval flow).
- Popover and dashboard show the deposit tx hash and the compute balance (no more dashes).
- Tests: cap respected, approval required above cap, failure safe-stops.

**E6. Opt-in and labelling (1 day)**
- Sponsored lines off until the developer turns them on in onboarding; "Sponsored" visible on the sign; pause, focus mode and quiet hours available from the menu bar.

**Exit criteria:** every paid view/click is signed and checkable; the contract is paused-able, multisig-operated, batched, and audited; the pet funds its own compute with a cap.

---

## Phase F: retention and attention (6–8 days)

**Developers**
- Earnings view in the popover and on `/me`: "today you waited 47 min and earned 0.03", from real wait-time (hook log) and confirmed settlements.
- Pet progression: levels from verified views and streaks; evolutions and skins **unlocked by level/streak** first. Paid cosmetics only later, and never in a way that reduces the developer's payout without consent.
- Streaks: daily coding streak keeps the pet happy (cosmetic only; never affects pay).
- Weekly recap card (opt-in share to X): time waited, earned, level. Generated server-side as an image from real numbers.
- Respect controls: frequency caps (per day, per campaign), quiet hours, focus mode, "relevant to my stack" detected locally (languages/frameworks from the repo) and never uploaded raw; only a coarse category list is sent if the user opts in.

**Brands**
- Real-time dashboard (C3) gains best-performing format, budget alerts (email + dashboard) at 50/80/100%, one-click top-up, auto-optimise toggle (B5).
- Weekly email report with views, unique humans, clicks, spend and top hook.

**Exit criteria:** week-2 retention and weekly-active pets are tracked; every number shown to a user is real.

---

## Phase G: deploy and distribution (5–7 days)

- **Web:** Vercel; env only in Vercel's encrypted env; preview deploys per PR.
- **Server:** Fly.io or Railway; Postgres managed; secrets in the provider's secret store; operator key via KMS (no raw key in env in production); health checks; Sentry.
- **Mac app:** Apple Developer account ($99/yr), Developer ID signing, notarised `.dmg`, Sparkle auto-update with signed appcast, crash reporting.
- **One-click "Connect Claude Code":** reads `~/.claude/settings.json`, backs it up, merges Gremlo's hook entries (never overwrites other hooks), shows the diff, and offers "Disconnect" that removes only Gremlo's entries. Same for Codex config.
- **Contract:** stays on Galileo until audit; mainnet afterwards with the multisig.
- **Observability:** Sentry (web, server), uptime checks, settlement and 0G-failure alerts.

**Exit criteria:** a new developer installs from a dmg, connects Claude Code in one click, registers with World, and sees a sponsored line, with no terminal.

---

## Phase H: Arkiv (2–3 days, optional, grant-driven)

- Only public-by-design data:
  - campaign public card (brand name, hooks chosen, rate, end time) with expiry = campaign end
  - hourly impression **batch receipts**: campaign, count, Merkle root of signed impression IDs, settlement tx; expiry = end + grace
- Not stored on Arkiv: brand briefs, proof points, per-user data, raw impressions.
- Postgres stays the source of truth; Arkiv is a public mirror the dashboard can verify against ("verified on Arkiv").
- Behind an interface so it can be switched off.

---

## Phase I: scale (ongoing)

- More agents: Codex, Cursor, Copilot agent mode via a small adapter interface (events → pet states).
- Windows and Linux companion (tray/edge, no notch), multi-monitor.
- Team pets and workplace controls (MDM-friendly off switch, org dashboards); "your office pet pays for the team's AI".
- Card payments for brands (Stripe → vault funding), stablecoin payouts.
- Legal: terms, privacy policy, ad disclosure, GDPR/CCPA, sanctions screening on payouts, tax reporting where required. No token.
- ENS identities on ENSv2 once registration is documented: `name.gremlo.eth` with live mood/status records.
- SDK for other wait surfaces (terminal status line, IDE status bar, CI dashboards).

---

## 3. Testing and quality (continuous)

| Layer | Tool | Lands in |
|---|---|---|
| Contract | Foundry unit, fuzz, invariant; audit before mainnet | A, E4 |
| Server | node:test; Postgres in CI | A onwards |
| Brain | node:test; claim validator table tests | B |
| Web | typecheck, `next build`, Playwright e2e on Anvil + stub 0G | A, C4 |
| Mac | `swift build`; unit tests for rotation, signing, settings merge | B, G |
| Runtime | Sentry, uptime, alerts on settlement failure and 0G errors | G |
| Release | manual QA checklist (below) | every release |

Release QA checklist: fresh install → connect Claude Code → register (World) → fund small campaign → pet shows hook → click opens URL → settle → dashboard shows tx → refund after end; plus 0G down → pet sleeps and says why; server down → pet sleeps and says why.

---

## 4. Metrics

- Developers: weekly active pets, opt-in rate to sponsored lines, wait-minutes per pet per day, payout per developer per month, week-2 retention, uninstall/ads-off rate.
- Brands: fill rate, effective price per 1,000 verified views, CTR per format, repeat campaigns, cost per verified human.
- Trust: voided views/clicks, flagged pets, disputed settlements (target: zero unexplained).

---

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Developers reject ads in their tools (npm 2019 precedent) | utility-first pet, opt-in only, clear "Sponsored", easy off, team pets |
| Click and view fraud | Secure Enclave signatures, World ID, holdback, fraud rules, no pay-per-click until E2 |
| AI hooks make false claims | deterministic claim validator + brand attestation + human pick |
| Platform risk (agent vendors change hooks/terms) | adapter layer for many agents, stay within each tool's documented hook API |
| Hot keys / contract bugs | KMS operator, multisig admin, pause, audit, batched settle tests |
| Free try-it abuse | per-IP limits, daily spend cap, cache |
| Crypto friction | card payments for brands, stablecoins for developers |
| Workplace bans | MDM-friendly off switch, org mode |

---

## 6. First two prompts (revised)

**Prompt 1 (Phase A1–A3 + B1–B2):**
> Create branch `v2` from `main`; never commit to `main`. Add GitHub Actions CI (forge, server, brain, web typecheck+build, mac swift build). Introduce `apps/server/src/db.ts` wrapping the current JSON store (no behaviour change), with tests. Then Phase B hook engine: brand brief form (product, audience, offer, proof points with an "ours and accurate" checkbox, CTA, https URL); `POST /campaigns/hooks` where 0G writes 2 hooks per format [humour, sarcasm, offer, question, bold-claim, urgency, story, dev-meme], max 80 chars, labelled Sponsored with the request ID; a deterministic validator in `packages/brain/claims.js` drops any hook with numbers, %, currency, multipliers, time claims or superlatives not present in the proof points/offer and reports why. Tests: validator table, prompt rule present, 16-hook shape, 0G failure path. Commit small; tests and builds green before each commit.

**Prompt 2 (B3–B5 + C):**
> On `v2`: brand picks 3–5 hooks; store them; `lineHash` = hash of the sorted set; `/campaigns/active` returns hooks + url; the Mac pet rotates hooks and tags impressions with hook_id. Clickable sign through the existing per-pixel hit-test: hover highlight, deliberate click → `GET /c/:campaign/:hook` signed redirect that logs a deduped click and 302s to the stored URL with UTM tags. Thompson-sampling rotation with a 15% floor until 200 views. Then the campaign success screen (live pet preview with the hooks as a ticker, receipt, budget, estimated views labelled estimate, share + dashboard) and a loading/success/error audit of every web action. Playwright e2e on Anvil with a test-only 0G stub: register → fund → settle → dashboard shows the tx. Commit small.

---

## 7. Rough total

A 5–7 · B 6–8 · C 4–5 · D 3–4 · E 8–12 (+ external audit) · F 6–8 · G 5–7 · H 2–3 → about **40–55 working days** for one developer with Claude Code, or about 4–6 weeks with two people splitting web/server and Mac. Mainnet waits on the audit.
