# GREMLO mainnet upgrade spec (for Claude Code)

Repo: https://github.com/DiveshK007/GREMLO (read at commit `b53a571`, 23 Nov 2026). Spec written 28 Nov 2026 (IST). Updated the same day with Divesh's decisions.
Owner: Divesh Kumar.S. Goal: turn the testnet hackathon build into a mainnet build with no god key, one real end-to-end flow, and docs that match what runs.

Everything below was checked against the repo and live chain state on 28 Nov 2026: file paths, function names, key lists on testnet, NEAR protocol version (88 on both networks), the `near` CLI syntax (near-cli-rs 0.31.1, every command form below was parsed with `--help`), and the NEAR and NEAR Intents docs. World ID docs were checked only as background; World ID is off (see Decisions). Where something could not be checked it says **VERIFY**.

### Decisions (28 Nov 2026, IST)

1. **World ID is completely off.** There is no "decide by 29 Nov noon" gate and no work to set it up for real. Keep the existing integration in the repo and keep the flags defaulting off. The only World ID task is to label it honestly as off/disabled in README.md, JUDGE.md and the What's real table (item 4). World ID hours are out of the core total, the timeline and the Claude Code prompt.
2. **Mainnet + one real flow is Milestone 1 and is ASAP.** A view settles on mainnet and pays for one TEE-signed NEAR AI call (item 1, about 6 to 7 h). Start immediately after BotFolio ships (BotFolio internal done-by **29 Nov, 9 PM IST**). Target by **30 Nov**. This replaces the earlier "Mon 30 Nov morning" slot: ASAP, right after BotFolio, target by 30 Nov. Contract v2 must still be frozen before that deploy (section 5), because the vault is locked after deploy and cannot be upgraded.
3. Later milestones, in this order: remove the god key (function-call key limited to four methods, locked vault about 5 h; on-chain `p256_verify` of the Mac Secure Enclave signature 8 to 10 h); per-pet purse at `<pet>.pets.gremlo.near` (3 to 4 h); docs, proof scripts, CI and video; NEAR Intents optional.
4. Never call the purse or the loop "self-funded". Stop and ask before any command that spends real NEAR.

---

## 0. Prompt to paste into Claude Code

Save this file in the repo as `docs/MAINNET_UPGRADE_SPEC.md` (untracked is fine), open Claude Code in the repo root, press Shift+Tab until Plan Mode is on, then paste this block:

````text
You are upgrading the GREMLO repo from a NEAR testnet hackathon build to a NEAR mainnet build.
The full spec is docs/MAINNET_UPGRADE_SPEC.md. Read all of it, plus CLAUDE.md, README.md, JUDGE.md, SECURITY.md, HANDOFF.md and docs/DEPLOY.md, before you plan.

Decisions already made (do not reopen):
- World ID is completely off. Do not set up a production World ID app, do not plan a "set it up for real" path, and do not add a noon decision gate. Keep the existing flag defaulting off. The only World ID work is to label it honestly as off/disabled in README.md, JUDGE.md and the What's real table (item 4).
- Priority Milestone 1 is a mainnet deploy plus one real flow: a view settles and pays for one TEE-signed NEAR AI call (item 1). Start that deploy ASAP after BotFolio ships (internal done-by 29 Nov, 9 PM IST), target by 30 Nov. Contract v2 must still be frozen before any mainnet deploy (section 5).
- Never claim "self-funded". You must STOP AND ASK before any command that spends real NEAR (rule 4).

Rules (hard):
1. PLAN MODE FIRST. Produce a plan that follows the priority milestones and the commit milestones M0-M6 in section 4, and the execution order in section 5, name the exact files you will touch, and wait for my approval. Do not edit anything before I approve.
2. Work on a branch named `mainnet-upgrade` (create it from main). Commit after every milestone and every green test run, with a real message. Never push to main, never force-push, never open a PR, never tag. Pushing the branch happens only when I say so.
3. Never commit secrets. Never read, print or paste .env files, private keys, seed phrases or keychain contents. `.claude/settings.json` already denies reads of .env and key files; do not work around it. Use env var names only. If you need a value, ask me.
4. MAINNET SAFETY. You may build, test, run sandbox and testnet commands and run read-only mainnet queries (view calls, `near account list-keys ... network-config mainnet now`). You must STOP AND ASK before any command that signs a mainnet transaction, spends real NEAR, creates or deletes a mainnet account or key, deploys code, or locks keys. Print the exact command and the NEAR it will spend, then wait for me to say go. Every script that can touch mainnet must default to dry-run (print the command, do nothing) and need `CONFIRM_MAINNET=yes` to run.
5. Do not touch the testnet deployment that the submission points at: `vault.gremlo.testnet`, `operator.gremlo.testnet`, the `hackathon-submission` tag, and the live API at https://16-4-100-95.sslip.io. Contract v2 deploys only to NEW accounts (sandbox, a testnet rehearsal vault such as `vault2.gremlo.testnet`, and mainnet).
6. Obey the repo's "Never fake" rules in CLAUDE.md: no mocked balances, tx hashes or completion ids; anything simulated is labelled on screen; never claim "self-funded" unless the loop ran with no manual top-up. Product copy follows the repo's voice (plain, short, no emoji).
7. Every claim you write in README.md, JUDGE.md or SECURITY.md must be backed by a command whose output I can see. Paste that output when you finish a milestone.
8. Order matters: contract v2 (M1) is frozen BEFORE any mainnet deploy, because the plan locks the vault after deploy and it can never be upgraded. Stop at each GATE in section 5 and report.
9. Money is integer yoctoNEAR (u128 / bigint), never floats. One test for every money or budget rule you touch.
10. At the end of each milestone report: what changed (files), test output, what is left, anything in the repo that contradicted the spec.

Start with M0 in plan mode.
````

Tip for the team: each teammate runs their own Claude Code session in a git worktree off the branch (`git worktree add ../gremlo-m2 -b mainnet-upgrade-m2 mainnet-upgrade`), commits there, and Divesh merges into `mainnet-upgrade` locally. No remote pushes needed.

---

## 1. Ground truth (what the repo and chain actually are today)

| Fact | Where | Checked how |
|---|---|---|
| Vault contract: Rust, near-sdk `=5.30.1`, Rust 1.95. Methods: `new`, `set_operator`, `register_pet` (payable, operator only), `set_verified`, `set_payout`, `set_compute_share`, `set_compute_cap`, `create_campaign` (payable), `top_up` (payable), `close`, `settle_impressions` (operator only), `charge_compute` (operator only, pays the operator), views | `contracts-near/src/lib.rs` (341 lines), tests in `contracts-near/tests/vault.rs` (near-workspaces sandbox, 18 integration tests, invariant `assert_invariant` line 85) | read |
| Settlement has no on-chain proof. `settle_impressions(id, pet_id, count)` trusts the operator's `count`; limits are the campaign budget and `SETTLE_GRACE` (3600 s) | `contracts-near/src/lib.rs` lines 221-244 | read |
| `register_pet` is `#[payable]` and the server attaches `PET_STORAGE_DEPOSIT` (0.01 NEAR). A function-call key cannot attach a deposit, so the operator cannot move to a function-call key until this changes | `contracts-near/src/lib.rs` 115-141, `apps/server/src/routes/pets.ts` line 48 and 71 | read + NEAR docs |
| `vault.gremlo.testnet`, `operator.gremlo.testnet`, `gremlo.testnet` each hold exactly ONE key and it is FULL ACCESS. Vault code hash `AeXXhh355asstWmnF9XzLHowUBoTXtAao7VR4WhF7gdb`, storage 189,886 bytes, balance about 3.006 NEAR | RPC `view_access_key_list` and `view_account`, 28 Nov | live query |
| Operator is a server hot key in env (`NEAR_OPERATOR_PRIVATE_KEY`), loaded by `newOperator()` in `apps/server/src/chain.ts`; every vault write goes through `send(methodName, args, deposit)` in the same file | `apps/server/src/chain.ts` lines 36-132 | read |
| Settlement worker: `workerPass()` every `WORKER_MINUTES` (default 10; the live server reports 1), `settle(id)` calls `send("settle_impressions", ...)`, `send("close", ...)`. Views wait `HOLDBACK_HOURS` (24 in `apps/server/Dockerfile` and `deploy/vm/gremlo-api.service`) | `apps/server/src/routes/settle.ts`, `batch.ts` (`planSettlement`, `markSettled`), `state.ts` line 214 | read |
| Device key is a P-256 key in the Mac's Secure Enclave. It signs `METHOD\nPATH\nunix_ms\nsha256hex(body)` as DER ECDSA (CryptoKit hashes with SHA-256). The server verifies in `checkSigned`/`canonical`/`deviceKey` and stores the exact body, key, time and signature in a hash-chained public log (`LogEntry` in `trust.ts`, `appendLog` in `routes/pets.ts`) | `apps/mac/Sources/Gremlo/main.swift` (`deviceSigner`, `deviceSign`), `Backend+Mac.swift` (`reportImpression`, `request`), `apps/server/src/auth.ts`, `trust.ts` | read |
| NEAR now has a native P-256 verify host function (`p256_verify`, NEP-635). Both mainnet and testnet are on protocol 88 and list `p256_verify_base = 1.3 Tgas`, `p256_verify_byte = 13 Mgas`. `near_sdk::env::p256_verify(&sig64, &prehash32, &pubkey33)` exists in near-sdk 5.30.1 (docs.rs 200) | RPC `EXPERIMENTAL_protocol_config` on `rpc.mainnet.fastnear.com` and `test.rpc.fastnear.com`; docs.rs | live query |
| Purse factory and purse are built, 14 tests, wasm committed (`gremlo_factory.wasm` 258,641 bytes, `gremlo_purse.wasm` 128,249). `Factory.create_pet(name, owner, owner_key, mac_key)` makes `<name>.<factory account>` with the owner's full-access key and the Mac's function-call key limited to `pay_inference` (allowance 0.25 NEAR). `Purse.pay_inference` only pays allow-listed providers, with per-call and daily caps, keeps a 0.5 NEAR reserve | `contracts-accounts/factory/src/lib.rs`, `purse/src/lib.rs`, `README.md` | read |
| The purse is already wired end to end: server `apps/server/src/purse.ts` (`purseFits`, `paymentMatches`, `spendable`, `overdue`), `routes/pets.ts` (`purseOf` line 355, `bill` 382, `pursePaid` 398, env `PURSE_PARENT`), Mac `Purse+Mac.swift` (`PurseController`, ed25519 key in Keychain) and `GremloCore/Near.swift` (`NearCall`, tested against near-api-js), web `Me.tsx`. Only deployment and two small fixes are missing | files listed | read |
| World ID is a complete IDKit v4 integration: `GET /world/sign` (`web.ts` `worldSign`), `verifyWorldProof` and `signalMatches`/`makeRegister` in `apps/server/src/register.ts`, IDKit request in `apps/web/app/(app)/pet/page.tsx` lines 120-135 with `environment: WORLD_ENV` from `apps/web/lib/config.ts`. "Simulated" means only `NEXT_PUBLIC_WORLD_ENV=staging` (`apps/web/.env.example`) | files listed | read |
| The server never checks the `environment` field of World's verify response, so a server pointed at production would still accept staging (simulator) proofs. World's docs say to assert `"production"` | `register.ts` `verifyWorldProof` | read vs docs.world.org |
| Live API on EC2 behind Caddy: `GET /health` ok, `/stats` = 3 campaigns, 2 settled views, 1 pet, 6e21 yocto paid, 1.2e21 charged | https://16-4-100-95.sslip.io | live query |
| Mainnet names are free: `gremlo.near`, `vault.gremlo.near`, `operator.gremlo.near` do not exist (UNKNOWN_ACCOUNT) | RPC | live query |
| NEAR price about $3.05 | CoinGecko, 28 Nov | live query |

### 1.1 Things that contradict the assumptions in the brief (read these)

1. **Bitty Beasts is on testnet and still made the shortlist.** Its README says "Live on NEAR testnet". So "testnet only" is not what kept Gremlo out by itself. What Bitty and Kibble have that Gremlo lacks: the pet IS a NEAR account or token, verification depth (Bitty checks raw Intel TDX quotes, nonce binding and the TD debug bit; Kibble's contract checks the enclave signature with `ecrecover`), and a track-fit story. Mainnet and no god key still matter (Kibble is mainnet with 185 live checks), but item 2B (on-chain checks) and item 7 (TEE depth) address the real gap.
2. **World ID is not "only simulated in code".** It is a full integration behind one env flag. The real gaps were: nobody has made a production proof yet, and the server does not assert `environment === "production"`. **Decision (28 Nov 2026, IST): leave it off.** Do not close those gaps in this upgrade. Label it honestly as off/disabled (item 4).
3. **The purse is further along than "built, not deployed".** Server, Mac and web are wired. Item 3 is mostly operations plus: the Mac's NEAR RPC default is hard-coded to testnet (`Purse+Mac.swift` line 14: `Legacy.env("NEAR_RPC") ?? "https://test.rpc.fastnear.com"`), and reserved sub-account names clash if the factory sits on `gremlo.near` (a pet named `vault` or `operator` would collide with the real accounts).
4. **The sub-account is `<pet>.pets.gremlo.near`, not `<pet>.<owner>.near`.** Only a parent account can create its sub-accounts, so `<pet>.<owner>.near` would need the owner to run a factory. The existing design (factory creates `<pet>.<factory account>`) is right. Deploy the factory to `pets.gremlo.near` so pet names can never clash with `vault`, `operator`, `admin`. `purseAccount(pet, parent)` in `apps/server/src/purse.ts` is generic, so `PURSE_PARENT=pets.gremlo.near` needs no code change.
5. **The operator cannot simply be given a function-call key.** `register_pet` is payable (see table). Fix: the owner registers their own pet and pays storage; the operator only calls `set_verified`.
6. **Purse spendable balance cannot be earned from views.** The purse keeps a 0.5 NEAR reserve plus about 1.3 NEAR storage stake, so the 0.0024 NEAR a view pays can never make it "spendable". The headline flow for item 1 therefore uses the vault compute-budget path (budget starts at 0, one view adds 0.0006 NEAR, one thought costs 0.0005 NEAR). The purse path (item 3) is a second, separate proof and is funded by the owner. Never call it self-funded.
7. **Views take 24 h to settle by default.** `HOLDBACK_HOURS=24` is baked into the Dockerfile and systemd unit. The mainnet demo instance needs `HOLDBACK_HOURS=0` (or 1) or the "real settle" will not happen in time.
8. **Doc drift to fix while you are there:** `docs/DEPLOY.md` line 5 says "Nothing here has been deployed yet" (the API is live on EC2); README line 82 links the text "Gremlo-1.0.2.dmg" to `.../download/v1.0.0/Gremlo-1.0.0.dmg`; `docs/WORLD_DEBRIEF.md` links a registration tx on the 0G chain from the earlier ETHGlobal build; README says the vault hash "matches a local build of contracts-near", which stops being true once contract v2 lands on main (the testnet vault matches tag `hackathon-submission`).
9. **`charge_compute` dedupes only the last completion id per pet** (comment in `contracts-near/src/lib.rs` line 251). An older id can be charged again. Acceptable on testnet; note it in the trust table or fix it with a per-pet rolling window (item 2).
10. **Shortlist context.** Kibble and Bitty both keep the AI's hands to function-call keys and show an attack demo or a one-command verify. Copy the pattern, not the code (see section 8).

---

## 2. Target architecture (what "done" looks like)

```
brand wallet --create_campaign--> vault.gremlo.near  (locked: ZERO access keys, code immutable)
Mac (Secure Enclave P-256) --signed view report--> API (operator FC key only)
API --settle_signed(report, device sig)--> vault: p256_verify on-chain, device registered by the pet owner on-chain
vault: pays owner payout, adds 20% to the pet's compute budget
API --charge_compute(completion id)--> vault (TEE-signed NEAR AI call, completion id in the event)
pet owner --create_pet--> pets.gremlo.near factory --> <pet>.pets.gremlo.near (purse)
Mac ed25519 FC key (pay_inference only) --> purse pays operator for one thought

operator.gremlo.near: server holds a FUNCTION-CALL key (receiver vault.gremlo.near, methods settle_signed, charge_compute, set_verified, close)
                      full-access key offline (cold), never on the server
gremlo.near (admin):  full-access key in macOS Keychain / Ledger, can only rotate the operator
vault.gremlo.near, pets.gremlo.near: all keys deleted after deploy and smoke test
```

What a stolen server (operator key) can still do after this work is listed in Appendix C. It cannot move the vault balance, change code, add keys, or create views that no registered Mac signed.

---
## 3. Work items, in priority order

Priority is impact on a judge (and on Divesh's risk). Execution order is different because contract changes must land before the one-time mainnet deploy; that order is in section 5. Time estimates are Claude Code assisted hours of focused work, not calendar time.

### Item 1. Mainnet deploy of vault and purse contracts, and ONE real end-to-end flow

**Goal.** One real view settled on NEAR mainnet pays a pet and funds its compute budget, and that budget pays for one TEE-signed NEAR AI call whose completion id is in the `compute_charged` event. Both transactions are linked in the README and checked by `npm run verify:public` against mainnet.

**Files to add or change**
- New `scripts/mainnet/` (all bash, `set -euo pipefail`, dry-run by default, `CONFIRM_MAINNET=yes` to run, each prints the command and the NEAR it spends): `common.sh` (reads `NETWORK`, refuses mainnet without the confirm var), `10-create-accounts.sh`, `20-deploy-vault.sh`, `25-deploy-factory.sh`, `30-operator-key.sh`, `40-smoke.sh`, `50-lock.sh`, `60-real-flow.md` (the human steps), `99-prove.sh`. Same scripts must run on `NETWORK=testnet` for the rehearsal (M3).
- `apps/server/src/chain.ts`: `rpcUrls` mainnet default has one URL (`https://rpc.mainnet.fastnear.com`); add a second failover. `https://archival-rpc.mainnet.fastnear.com` answers `status` today. **VERIFY** any other mainnet RPC before adding it. `explorer`, `network` and `seeded` already branch on `NEAR_NETWORK`.
- `apps/server/.env.example`, `apps/web/.env.example`: add a commented mainnet block (names only).
- `deploy/vm/gremlo-api-mainnet.service` (copy of `gremlo-api.service`: `PORT=8788`, `EnvironmentFile=/etc/gremlo/mainnet.env`, `STORE_PATH=/data/gremlo-mainnet/data.json`, `LOG_DIR=/data/gremlo-mainnet/logs`, `GALLERY_DIR=/data/gremlo-mainnet/gallery`, `HOLDBACK_HOURS=0` for the demo, raise to 1 after) and a second site block in `deploy/vm/Caddyfile` for `mainnet.16-4-100-95.sslip.io` to `127.0.0.1:8788`. A second instance leaves the live testnet submission untouched. `docs/DEPLOY.md` gets a "Mainnet instance" section.
- `apps/web`: a second Vercel project (same repo, `apps/web` root) with mainnet env. `apps/web/lib/config.ts` already switches `NETWORK`, `EXPLORER` and default RPCs on `NEXT_PUBLIC_NEAR_NETWORK`. Make `apps/web/app/(app)/experience/page.tsx` network-aware: it hard-codes "testnet" in lines 22, 35, 42, 49, 52, 224, 294, 339, 362-364 and 487. Read `NETWORK` and `VAULT_ID` instead.
- `apps/server/scripts/verify-public.ts` and `fixtures/public-proof.mainnet.json`: see item 5.

**Implementation steps**
1. Build the contract artifact only after M1 is frozen (gate G1): `cd contracts-near && cargo near build non-reproducible-wasm` (output lands in `contracts-near/target/near/campaign_vault.wasm`; the vault wasm is not committed, unlike the factory and purse wasm in `contracts-accounts/res/`). If Docker is available, also try `cargo near build reproducible-wasm` (**VERIFY** the metadata block it needs in `Cargo.toml` against the cargo-near docs) and record both hashes. Record `sha256`, base58 code hash and the git commit in `fixtures/public-proof.mainnet.json`.
2. Create accounts (script 10; see Appendix A for the verified command forms): `gremlo.near` (admin, funded from Divesh's wallet), then sub-accounts `vault.gremlo.near`, `operator.gremlo.near`, `pets.gremlo.near`, `brand.gremlo.near`. Each gets a generated full-access key saved to the macOS keychain (`save-to-keychain`) or a Ledger if Divesh has one.
3. Deploy and initialise the vault in ONE transaction (`near contract deploy ... with-init-call new ...` with `{"admin":"gremlo.near","operator":"operator.gremlo.near"}`), then run read-only checks: `get_admin`, `get_operator`, `get_totals`, `near contract inspect vault.gremlo.near network-config mainnet now`.
4. Give the operator its function-call key (item 2A), put that private key into `/etc/gremlo/mainnet.env` on the EC2 box via `sudoedit` (root-only, mode 600; see `docs/DEPLOY.md` "Secrets"). It is never pasted into chat, a repo file or a shell history.
5. Start the mainnet API instance with `NEAR_NETWORK=mainnet`, `NEAR_CONTRACT_ID=vault.gremlo.near`, `NEAR_OPERATOR_ACCOUNT_ID=operator.gremlo.near`, `NEAR_OPERATOR_PRIVATE_KEY=<function-call key>`, `COMPUTE_FEE_SMART_YOCTO`/`COMPUTE_FEE_CHEAP_YOCTO` unchanged, `HOLDBACK_HOURS=0`, `WORKER_MINUTES=1`. Leave World ID off (item 4): do not set production World env vars; keep the existing flags at their defaults (off). `GET /health` must be 200.
6. Smoke test with tiny values (script 40): `brand.gremlo.near` creates campaign 1 with 0.2 NEAR at rate 0.003 NEAR/view and a 1-hour window; register and verify a pet; settle one signed view; charge one compute call. If anything fails, fix it while the admin can still redeploy (before the lock).
7. Lock (item 2A step 6, gate G3). THEN run the real flow on the locked contract so the README claim "ran on the locked contract" is true:
   a. Divesh's Mac with `GREMLO_SERVER=https://mainnet.16-4-100-95.sslip.io GREMLO_WEB=<mainnet vercel url> NEAR_RPC=https://rpc.mainnet.fastnear.com` (for an app opened from Finder: `launchctl setenv`, then reopen; see `docs/DEPLOY.md` section 3). Pair the Mac (item 2B step 5).
   b. Start a Claude Code run, let the sign show 5 s, wait for the worker (`worker: settled campaign 1` in `journalctl -u gremlo-api-mainnet -f`).
   c. The pet thinks (smart tier needs at least 0.0005 NEAR in budget: one 0.003 NEAR view adds 0.0006). Confirm `compute_charged` with a `chatcmpl-...` id.
   d. `cd apps/server && NEAR_AI_API_KEY=... npm run verify <completion_id>` must print SIGNED. Paste the output into PROOF.md.
8. Add a "Mainnet run" section to README.md (Proof) and PROOF.md with both tx hashes, nearblocks mainnet links (`https://nearblocks.io/txns/<hash>`), account ids, code hash, block heights and the date.

**Acceptance criteria**
- `near account list-keys vault.gremlo.near network-config mainnet now` shows no keys.
- `get_totals` on mainnet satisfies `paid_to_pets + compute_budgets + compute_charged + remaining + refunded == total_deposited`.
- A mainnet `settle_signed` tx and a mainnet `charge_compute` tx with a TEE completion id exist and are linked; `npm run verify <id>` says SIGNED.
- `npm run verify:public` on the mainnet fixture exits 0.
- The testnet submission (`vault.gremlo.testnet`, the live API, tag `hackathon-submission`) is unchanged: `npm run verify:public` with the testnet fixture still exits 0.

**Verification commands**
```bash
near account list-keys vault.gremlo.near network-config mainnet now
near contract call-function as-read-only vault.gremlo.near get_totals json-args '{}' network-config mainnet now
near contract inspect vault.gremlo.near network-config mainnet now        # no settle_impressions in the list
curl -s https://mainnet.16-4-100-95.sslip.io/health
cd apps/server && npm run verify:public -- --fixture fixtures/public-proof.mainnet.json
cd apps/server && NEAR_AI_API_KEY=... npm run verify <completion_id>
```

**Estimate.** 6 to 7 h: scripts and config 3 h, instance setup 1 h, Divesh hands-on mainnet 2 to 3 h, evidence 1 h. Excludes contract v2 (item 2).

---

### Item 2. Remove the god key

Split in three so a partial result is still honest: **2A** (must), **2B** (should, the strongest part), **2B-lite** (fallback if 2B is not green at gate G1).

#### 2A. Function-call operator key, locked vault, proof scripts

**Goal.** The server holds a function-call key that can call only `settle_signed`, `charge_compute`, `set_verified`, `close` on the vault; it has no withdraw method to call and cannot attach NEAR. The vault and factory accounts have zero keys. A script anyone can run proves it.

**Files**
- `contracts-near/src/lib.rs`:
  - `register_pet`: remove `self.only_operator()`; the caller becomes the owner (`env::predecessor_account_id()`), drop the `owner` argument, keep the storage-from-deposit logic (`before`/`cost`/refund) as is. New signature `register_pet(pet_id: String, payout: AccountId)`. Reason: a function-call key cannot attach a deposit, and the operator should not pay storage for strangers anyway.
  - `set_verified` stays operator-only; unverified pets already cannot be settled (`require!(pet.verified, "PetNotVerified")`).
  - Add `set_paused(paused: bool)` (admin) and a `paused` field; `settle_signed` and `charge_compute` start with `require!(!self.paused, "Paused")`. This is the incident brake that needs no upgrade. (SHOULD, 30 min.)
  - Add a `version()` view returning `"2.0.0"`.
  - Mainnet is a fresh deploy, so struct changes need no migration. Do not reuse the `last_charge_key` raw-key trick for new fields.
- `contracts-near/tests/vault.rs`: rewrite `register_pet_operator_only_once_with_storage` (line 152) to "owner registers, pays storage, only once, operator cannot register"; keep `assert_invariant` in `random_operations_keep_the_invariant` (line 388); add `paused_blocks_money_out`.
- `apps/server/src/routes/pets.ts`: in `registerPet = makeRegister({... registerOnChain ...})` (about lines 64-77) stop calling `send("register_pet", ...)` and delete `PET_STORAGE_DEPOSIT` (line 48). New order: owner signs `register_pet` from their wallet, THEN the World proof is verified, THEN the server requires `get_pet(name).owner === body.owner` on chain and calls `send("set_verified", { pet_id, verified: true })`.
- `apps/server/src/register.ts` `makeRegister`: keep the order "World first, then name clash"; the `registerOnChain` dep now means "verify an existing on-chain pet".
- `apps/web/lib/chain.ts`: add `registerPet(account, name, payout)` next to `createCampaign` using the existing `call()` helper with a 0.01 NEAR deposit (the vault refunds the unused part); `apps/web/app/(app)/pet/page.tsx`: call it before the IDKit step (see lines 120-141) and show the tx.
- `apps/server/src/routes/health.ts`: `/health` already fails below 0.5 NEAR operator balance; also read the operator's access key (`query view_access_key`) and report `allowanceLeft`; 503 under 0.2 NEAR of allowance so the function-call key never silently runs dry (an exhausted allowance cannot be raised; a new key is needed).
- New `apps/server/scripts/prove-keys.ts` (`npm run prove:keys`): read-only, no env needed. For vault, factory and each purse: `view_access_key_list`. PASS only if the vault and factory have zero keys; the operator account has only function-call keys whose `receiver_id` is the vault and whose `method_names` are a subset of the allow-list and contain no admin method; purse accounts have exactly one full-access key (the owner's) plus the Mac's function-call key limited to `pay_inference`; `view_account` code hash equals the recorded one. Prints one line per claim and exits 1 on any failure.
- New `apps/server/scripts/attack-demo.ts` (`--check` read-only, `--live` needs the operator function-call key and spends under 0.01 NEAR of gas): the Kibble pattern (see section 8). With the operator's real key it tries: transfer NEAR (expect `RequiresFullAccess`), add a key (`RequiresFullAccess`), deploy code (`RequiresFullAccess`), call `set_operator` (`MethodNameMismatch`), call `register_pet` (`MethodNameMismatch`), settle with a bad signature (contract panic), replay a used signature (contract panic), `charge_compute` over budget (`OverComputeBudget`). Save the output to `docs/ATTACK-DEMO.md` with tx links for the contract-level refusals.
- New `docs/TRUST.md`: the table in Appendix C.

**Implementation steps** (commands in Appendix A)
1. Rehearse everything on testnet first (M3) with throwaway accounts, including the lock.
2. After the vault is deployed and smoke-tested on mainnet, add the operator function-call key:
   `near account add-key operator.gremlo.near grant-function-call-access --allowance '2 NEAR' --contract-account-id vault.gremlo.near --function-names 'settle_signed,charge_compute,set_verified,close' autogenerate-new-keypair print-to-terminal network-config mainnet sign-with-keychain send`
   The CLI prints the private key once; paste it straight into `/etc/gremlo/mainnet.env`, nowhere else.
3. Point the server at that key, restart, run one settle and one charge through it.
4. Keep the operator account's full-access key off the server, in the owner's keychain. The operator account only holds gas money plus the fees `charge_compute` pays it; sweep it with the full-access key when needed.
5. Keep `gremlo.near` (admin) full-access key in the keychain or on a Ledger. The admin can only call `set_operator`, `set_paused`; it cannot move vault funds or change code. A stolen admin key can still swap the operator, so keep it cold.
6. LOCK (gate G3, irreversible): check the deployed code hash equals the recorded one, check `get_admin`/`get_operator`/`get_totals`, then delete every key on `vault.gremlo.near` and `pets.gremlo.near`:
   `near account delete-keys vault.gremlo.near public-keys ed25519:<KEY> network-config mainnet sign-with-keychain send`
   `near account list-keys vault.gremlo.near network-config mainnet now` must print no rows. After this nobody can upgrade or move funds except through the contract's own methods. Decision recorded in SECURITY.md: immutable by design; a bug means deploying a new vault account and migrating by hand.
7. `docs/ATTACK-DEMO.md` generated from `--live`.

**Acceptance criteria**
- `npm run prove:keys` exits 0 against mainnet and prints one PASS line per claim.
- `near account list-keys vault.gremlo.near network-config mainnet now` shows no keys; same for `pets.gremlo.near`.
- `near account list-keys operator.gremlo.near network-config mainnet now` shows one full-access key (cold, not on the server) and one function-call key with the four methods.
- `npm run attack-demo -- --check` lists the keys and what each can call; every `--live` step is refused.
- `cargo test` in `contracts-near` passes, including the invariant test.

**Verification commands**
```bash
cd contracts-near && cargo test
cd apps/server && npm test && npm run typecheck && npm run prove:keys
cd apps/server && npm run attack-demo -- --check
near account list-keys vault.gremlo.near network-config mainnet now
near account list-keys operator.gremlo.near network-config mainnet now
```

**Estimate.** 5 h (contract tweaks 1.5 h, server/web 1.5 h, two scripts 2 h).

#### 2B. The contract verifies the Secure Enclave signature on-chain

**Why this is possible now.** The Mac already signs every view report with a P-256 key (`deviceSign` in `apps/mac/Sources/Gremlo/main.swift`), and NEAR has a native `p256_verify` host function on both networks (protocol 88, 1.3 Tgas, `near_sdk::env::p256_verify`). The signed message is `POST\n/impressions\n<unix ms>\n<sha256 hex of body>` and the body, key, time and signature are already stored per counted view in the public log (`LogEntry`, `appendLog`). So **no Mac change is needed**: the server converts the signature to raw form and the contract re-derives the digest and verifies.

**What it proves, honestly.** Only a Mac whose Secure Enclave key the owner registered on-chain can produce a view the vault will pay. The operator can no longer invent or inflate views. It does not prove a human was at the screen: the Mac app itself reports `unlocked`, `visible`, `shownMs`, `idleS`, so someone running a modified app on their own registered Mac can still cheat, within the on-chain caps. Do not claim more. The operator is still trusted for `set_verified` (the World ID attestation); see Appendix C.

**Contract design** (`contracts-near/src/lib.rs`; interface sketch in Appendix D)
- `Pet` gets `devices: Vec<Device>` with `Device { key: [u8; 33], last_time_ms: u64 }` (at most 5), plus `view_day: u64` and `views_today: u32`.
- `add_device(pet_id, device_key)` (payable, pet owner only; key is 33-byte compressed SEC1, first byte 2 or 3; storage paid from the deposit, rest refunded) and `remove_device(pet_id, device_key)`. Pairing becomes an on-chain owner transaction.
- `settle_signed(id: u64, pet_id: String, reports: Vec<SignedReport>) -> u64` (operator only, at most 20 reports per call, 300 Tgas), where `SignedReport { device_key: Base64VecU8, time_ms: u64, body: String, sig: Base64VecU8, accepted: u32 }`. For each report, in ascending `time_ms`:
  1. the device key is registered on the pet;
  2. `time_ms > device.last_time_ms` (this is the replay guard; it also makes the signature's malleability irrelevant); then store it;
  3. `time_ms` is not more than 5 minutes ahead of the block time, not older than 7 days, and `time_ms / 1000 <= campaign.end_time`;
  4. `message = format!("POST\n/impressions\n{time_ms}\n{hex(sha256(body))}")`, `digest = env::sha256_array(message.as_bytes())`, `env::p256_verify(&sig, &digest, &key)` must be true;
  5. parse `body` (near-sdk re-exports `serde_json`): rows of `{petKey, campaignId (string or number), shownMs, unlocked, visible, idleS}`; count rows with `petKey == pet_id`, `campaignId == id`, `unlocked && visible && shownMs >= 5000 && idleS <= 300` (the constants `MIN_SHOWN_MS`, `MAX_IDLE_S` in `apps/server/src/viewable.ts`);
  6. `n = min(count, accepted)`; apply the per-pet daily cap of 120 views (`DAILY_VIEW_CAP` in `apps/server/src/batch.ts`) keyed by the report's UTC day; reject a report whose day is before `pet.view_day`.
  Total `count = sum(n)`; then reuse the existing payout and compute-share math in one shared internal function (extract it from `settle_impressions`: the `amount`, `compute`, `paid` block and the `totals` updates) so the invariant still holds.
- `settle_impressions` is compiled out of the mainnet build with a cargo feature (`legacy-settle`, off by default). `near contract inspect` on mainnet must not list it. The existing tests run under `--features legacy-settle`; new tests cover the signed path. The v2-lite fallback is the same code built with that feature on.
- Event `impressions_settled` adds `device` (first 8 bytes of the key, hex) and `reports`.

**Server changes**
- `apps/server/src/auth.ts`: add `compressP256(x963: Buffer): Buffer` (prefix `0x02 | (y[31] & 1)` then X) and `derToRaw(der: Buffer): Buffer` (ASN.1 `30 len 02 lenR R 02 lenS S`, strip leading zeros, left-pad each to 32 bytes). Unit tests: sign with Node `crypto.sign("sha256", msg, { key, dsaEncoding: "ieee-p1363" })` and compare with `derToRaw` of the DER form; compress a known key; shared test vectors in `apps/server/fixtures/receipt-vectors.json` that the Rust tests also load.
- `apps/server/src/routes/pets.ts` `addImpressions` and `apps/server/src/state.ts`: when a row is counted, remember which public-log entry backs it (`logHeads` and the entry `i`) next to the `held` bucket (`hold(...)` in `fraud.ts`) so the worker can fetch `{body, key, time, sig}` from the log (`logFile(id)` in `state.ts`, read via the code behind `publicLog` in `routes/campaigns.ts`).
- `apps/server/src/batch.ts` `planSettlement`/`markSettled` and `routes/settle.ts` `settle(id)`: build `reports` sorted by `time`, at most 20 per tx, send `settle_signed`, and mark settled by the count the contract returns (it is the authority).
- `apps/server/src/routes/pets.ts` `pairDevice`: keep the NEP-413 HTTP pairing; additionally require the device key to be registered on-chain (`get_pet.devices`) before a view is queued for settlement.
- `apps/web/app/(app)/pair/page.tsx` and `apps/web/lib/chain.ts`: after the NEP-413 signature, send `add_device` from the owner's wallet (0.005 NEAR deposit, refund of the unused part) and show the tx. A reinstalled Mac has a new Secure Enclave key and must be added again.

**Acceptance criteria**
- Sandbox tests: valid report pays; same report twice fails; older `time_ms` fails; unregistered key fails; tampered body fails; key of another pet fails; `shownMs` 4999 counts zero; day cap at 120 holds; invariant still holds in the random-operations test.
- A report produced by a real Mac (capture one from the public log of the testnet rehearsal, not from a fixture) verifies on-chain.
- On the mainnet vault the method list has no `settle_impressions`.
- Gas for a 20-report call stays under 150 Tgas on the sandbox.

**Verification commands**
```bash
cd contracts-near && cargo test && cargo test --features legacy-settle
cd apps/server && npm test
curl -s https://<server>/campaigns/1/log | jq '.entries[0] | {key, time, sig}'      # the evidence the contract checks
near contract inspect vault.gremlo.near network-config mainnet now | grep -c settle_impressions   # expect 0
```

**Estimate.** 8 to 10 h (contract 4 h, server 3 h, web 1 h, tests and vectors 2 h). Gate G1 decides whether it ships (section 5).

#### 2B-lite (fallback if 2B is not green at G1)

Keep `settle_impressions` (build with `--features legacy-settle`) and add an anchor so the operator's claims are auditable: `settle_impressions` gains `log_head: String` (the hex `hash` of the last public-log entry for that campaign, from `logHeads` in `state.ts`) and emits it in `impressions_settled`. `prove-keys.ts` or `verify-public.ts` then fetches the campaign log, replays it with the logic behind `gremlo verify` (`GremloCore/Verify.swift`, `verifyLog` in `trust.ts`) and checks that the anchored head is in the chain. README says plainly: "views are operator-settled; the operator cannot rewrite the public log after the fact." 2 h.

---

### Item 3. Per-pet sub-account that owns the compute budget, with a spend-only key

**Goal.** A pet has its own NEAR account `<pet>.pets.gremlo.near` (the purse). The owner holds its full-access key. The Mac holds only an ed25519 function-call key limited to `pay_inference`, which can pay only the allow-listed provider within a per-call and a daily cap. One real thought is paid from it on mainnet.

**What exists.** All of it: `contracts-accounts/factory/src/lib.rs` (`create_pet`, `on_created`), `purse/src/lib.rs` (`pay_inference`, `set_caps`, `set_providers`, `withdraw`, `RESERVE`), `apps/server/src/purse.ts`, `routes/pets.ts` (`purseOf`, `bill`, `pursePaid`, `purseGate`), `apps/mac/Sources/Gremlo/Purse+Mac.swift`, `GremloCore/Near.swift`, `apps/web/app/(app)/me/Me.tsx`. 14 contract tests. Do not redesign it.

**Files to change**
- `apps/mac/Sources/Gremlo/Purse+Mac.swift` line 14: replace the testnet default. Read the RPC from the server (`backend.info?.rpc`), then `NEAR_RPC`, then the testnet default. Add `rpc: String?` to the info model in `apps/mac/Sources/Gremlo/Models+Mac.swift` (the struct that already has `explorer`, line 19) and return `rpc: rpcUrls[0]` next to `explorer` in `apps/server/src/routes/pets.ts` (about line 242). Also `Backend+Mac.swift` line 596 falls back to the testnet explorer; keep it as a fallback only.
- `apps/mac/Sources/Gremlo/Phone+Mac.swift` line 133 opens `<explorer>/address/<petName>`; it should open the purse account when `info.purse` exists.
- `contracts-accounts/README.md`: add a mainnet section using the commands below; `docs/DEPLOY.md` "The pet's purse" section too.
- New `scripts/mainnet/25-deploy-factory.sh` and `70-create-purse.sh`.
- Optional (SHOULD NOT block): a "Create the pet's purse" button on `Me.tsx` that calls `create_pet` through the wallet. **VERIFY** that NEAR Connect's `getAccounts()` returns the owner's public key; otherwise stay with the script.

**Implementation steps**
1. `cd contracts-accounts && cargo test` (14 tests). Record `sha256sum res/gremlo_factory.wasm res/gremlo_purse.wasm`. Deploy the committed wasm; do not rebuild unless the tests need it (a rebuild with a different toolchain changes the hash).
2. Factory on `pets.gremlo.near` (parent decides names; this avoids clashes with `vault` and `operator`):
   `near contract deploy pets.gremlo.near use-file contracts-accounts/res/gremlo_factory.wasm with-init-call new json-args '{"providers":["operator.gremlo.near"],"per_call":"500000000000000000000","daily":"10000000000000000000000"}' prepaid-gas '30 Tgas' attached-deposit '0 NEAR' network-config mainnet sign-with-keychain send`
   (`new` is `#[private]`, so it must run in the account's own deploy transaction; `per_call` must be at least `COMPUTE_FEE_SMART_YOCTO`.)
3. Pair step on the Mac: Settings, Phone and Mac, The pet's purse, Copy, to get the Mac's `ed25519:` purse key.
4. Create the purse (owner signs, 2 NEAR covers about 1.3 NEAR storage and the 0.5 NEAR reserve, leaving about 0.2 NEAR spendable, enough for hundreds of thoughts at 0.0005):
   `near contract call-function as-transaction pets.gremlo.near create_pet json-args '{"name":"<pet>","owner":"<owner>.near","owner_key":"ed25519:<owner public key>","mac_key":"ed25519:<from the Mac>"}' prepaid-gas '100 Tgas' attached-deposit '2 NEAR' sign-as <owner>.near network-config mainnet sign-with-keychain send`
5. Server: add `PURSE_PARENT=pets.gremlo.near` to `/etc/gremlo/mainnet.env`, restart. `purseFits` requires the purse's `owner` to equal the pet's owner and `operator.gremlo.near` to be in `providers` (it is, from the factory init).
6. Run item 1's real flow first on the vault budget (no purse yet), THEN create the purse for the same pet and trigger one more thought. The server's `purseOf` re-checks every 30 s and from then on bills the purse. One human gets one pet (World nullifier), so do not plan on a second pet.
7. Evidence: the purse's `paid_for_thinking` event (provider, amount, request id), the `/me` page "Pays from <pet>.pets.gremlo.near", and `near account list-keys <pet>.pets.gremlo.near network-config mainnet now` showing one full-access key (owner) and one function-call key (receiver is the purse itself, method `pay_inference`). Extend `attack-demo.ts --live` with: Mac key calls `withdraw` (expect `MethodNameMismatch`).
8. Never call this "self-funded". The purse was funded by the owner's 2 NEAR deposit. Say "paid from the pet's own account".

**Acceptance criteria**
- `near account view-account-summary` or `view_account` for `<pet>.pets.gremlo.near` shows the purse code and its balance; `get_purse` returns the caps.
- A `pay_inference` mainnet tx signed by the Mac's function-call key exists, `paymentMatches(...)` accepted it (server log `purse: <pet> paid ... tx ...`), and `/pets/<pet>` shows `purse.account`.
- The Mac key cannot call anything but `pay_inference` (the key list proves it; the attack demo shows a refusal).

**Verification commands**
```bash
cd contracts-accounts && cargo test
near contract call-function as-read-only <pet>.pets.gremlo.near get_purse json-args '{}' network-config mainnet now
near account list-keys <pet>.pets.gremlo.near network-config mainnet now
curl -s https://mainnet.16-4-100-95.sslip.io/pets/<pet> | jq .purse
cd apps/server && npm run prove:keys
```

**Estimate.** 3 to 4 h. Savings option for the hackathon: skip the factory and deploy the purse wasm straight to `<pet>.gremlo.near` with `with-init-call new` (saves about 3.5 NEAR) but then pets are not self-serve; prefer the factory since it is built and tested. Global contracts (NEP-591) are not worth it for one pet: publishing the 128 KB purse globally burns about 12.8 NEAR (10 NEAR per 100 KB, docs.near.org/smart-contracts/global-contracts). Mention as the scale path (Bitty Beasts uses it).

---

### Item 4. World ID is off: label it honestly

**Decision already made (28 Nov 2026, IST): World ID is completely off.** There is no "decide by 29 Nov noon" gate, and no work to set up a production World ID app, Orb access, or a real phone proof. Do not reopen this. Do not plan a production World ID path.

**What to do**
- Leave the existing IDKit v4 integration in the repo. Do not delete it, and do not turn it on.
- Keep the flags defaulting off. Do not set `NEXT_PUBLIC_WORLD_ENV=production` (or any production World app id, RP, or `RP_SIGNING_KEY`) on the mainnet instance, in Vercel, or in `.env.example`. The mainnet server must start without World env vars and must not require a World proof to register a pet (owner-signed registration from item 2 is the path).
- Do not call `set_verified` as a stand-in for a human check. Never present a mainnet pet as a verified human.
- In `README.md` (the "What's real" table, lines 147-168, and any "one human, one pet" badge or copy), in `JUDGE.md` ("What is simulated"), and in any other what's-real table: say plainly that World ID is built and was used on the testnet simulator, and is **off / disabled on mainnet**.
- The `/pet` page on the mainnet web app must not invite the user to "Scan with World App" or "Verify with the World ID simulator" as if it were live.

**Acceptance.** A reviewer who reads only the README and JUDGE.md understands World ID is off on mainnet. The mainnet instance does not call World's production API. No pet is labelled a verified human. **Estimate.** About 0.5 h, done as part of item 5. Not a separate line in the core hour total.

---

### Item 5. README, JUDGE.md, what's-real table, proof script, demo checklist

**Goal.** Every sentence a judge reads matches something they can run. Judges need no Mac: the guided tour, the API, `verify:public` and the recorded video are the path.

**Files and exact edits**
- `README.md`: badge line 31 (`NEAR-testnet`) to mainnet with a testnet note; "Judging?" block lines 38-47 (stats curl URL, vault names, "Last verified" date and the check count); Proof section lines 122-145 (add a "Mainnet run" table above the testnet one; keep testnet as history with its tag); "What's real" lines 147-168 (rows: Vault, The full loop, TEE-signed inference, World ID, The pet's own purse, Mainnet, plus a new row "No god key" and "Views signed by the Secure Enclave verified on-chain" if 2B shipped; known limits: delete the full-access-key bullet if the lock ran, keep "AI billed at a fixed NEAR rate per tier", keep Mac-only); repo map line 218 ("Factory and purse (not deployed)" becomes deployed if item 3 ran); line 82 dmg link text vs URL mismatch.
- `JUDGE.md`: "What is simulated" (lines 19-24), "Known limits" (lines 32-38: remove "Testnet only", "Views are settled by the operator" and "The vault has a full-access key" only where they stop being true), add the mainnet judge path: three commands (`curl .../stats`, `npm run prove:keys`, `npm run verify:public -- --fixture fixtures/public-proof.mainnet.json`).
- `SECURITY.md`: Keys table (lines 7-14) and the "full-access key" section (lines 22-30): rewrite to what is now true, include the Appendix C table, say the contract is immutable and what that means.
- `docs/TRUST.md` (new, Appendix C), `docs/ATTACK-DEMO.md` (generated), `docs/DEPLOY.md` (line 5 stale; add the mainnet instance and a locked-vault note), `HANDOFF.md` (env names), `PROOF.md` (mainnet section), `CHANGELOG.md`, `contracts-accounts/README.md`.
- `apps/server/scripts/verify-public.ts`: parameterise by `--fixture <path>`; it hard-codes `https://test.rpc.fastnear.com` in two places (code hash and `/stats` blocks), use `fx.rpcLive` from the fixture instead; mainnet archival RPC for `EXPERIMENTAL_tx_status`: `https://archival-rpc.mainnet.fastnear.com`. Add checks: key policy (call the logic of `prove-keys.ts`), the `get_totals` invariant, the completion id present in the `compute_charged` log of the flow tx, the code hash against `fixtures`, and `/stats` agreeing with the chain. `package.json`: add `"verify:public:mainnet"` and `"prove:keys"`. `.github/workflows/ci.yml` job `proof`: run both fixtures.
- New `apps/server/fixtures/public-proof.mainnet.json`: same shape as `public-proof.json` (`network`, `vault`, `codeHash`, `rpc`, `api`, `minPaidYocto`, `minComputeChargedYocto`, `txs[]`) plus `policy` (key rules) and `commit`.
- Optional, cheap, and the Kibble lesson: a `/prove` page in `apps/web` that runs the key-list and totals checks in the browser with the JSON-RPC helpers in `apps/web/lib/chain.ts`. 2 h; skip if time is short.

**Acceptance criteria**
- A fresh clone: `cd apps/server && npm ci && npm run verify:public:mainnet && npm run prove:keys` exits 0 with no keys and no `.env`.
- Every line in the README "What's real" table has a command or link that shows it. Nothing says "testnet only" while mainnet is live, and nothing says "mainnet" for a part that only ran on testnet.
- `npm test` in `apps/server`, `apps/web`, `packages/brain`, `cargo test` in both contract crates all pass; CI is green on the branch.

**Demo recording checklist (30 to 45 s, /brag-style, cut for X)**

Capture these BEFORE editing, from the real mainnet run, all with the mainnet server:
1. Screen recording: Claude Code starts a run, the notch pet drops out, the AD line shows on its sign (labelled AD).
2. Menu bar panel or `/me`: the signed view counted.
3. Terminal: `journalctl` line `worker: settled campaign 1` or the `/live` page showing the settle.
4. nearblocks mainnet page for the `settle_signed` tx, scrolled to the `impressions_settled` event.
5. The pet thinking, then the `compute_charged` event with `chatcmpl-...` and `npm run verify <id>` printing SIGNED.
6. Terminal: `npm run prove:keys` all PASS and `near account list-keys vault.gremlo.near network-config mainnet now` showing no rows.
7. (If item 3) the purse `pay_inference` tx.

| Time | Beat | On screen | Voiceover or caption |
|---|---|---|---|
| 0-4 s | Hook | Claude Code run starts, pet drops from the notch | "Your agent makes you wait. Gremlo makes the wait pay." |
| 4-10 s | The ad | Sign with the AD line, 5 s counter | "A brand pays for one line. It shows only while your agent works." |
| 10-17 s | Settle | Signed view, then the mainnet tx | "The Mac signs the view with its Secure Enclave. The vault checks the signature on-chain and pays." |
| 17-25 s | Thought | Pet thinks, `chatcmpl` id, SIGNED | "The wait pays for the pet's next thought, signed by a NEAR AI enclave." |
| 25-34 s | No god key | `prove:keys` PASS lines, empty key list | "The vault has no keys. Nobody can change it or take the money." |
| 34-40 s | Close | Logo, repo link, mainnet explorer link | "Real mainnet NEAR, a few cents. Gremlo." |

Copy rules: say "a few cents of real NEAR"; no profit or earning claims; do not say "self-funded"; say "paid from the pet's own account" only on the purse beat; do not claim a human was verified (World ID is off); do not claim a tx hash until the explorer shows it final. The X post goes out only through a `create_posts` draft card that Divesh approves word for word, from @diveshbuilds. If /brag bundled music is used again, include the credit in the post text: "Drums: MuldjordKit by Lars Muldjord (CC BY 4.0)".

**Estimate.** 4 to 5 h docs and scripts, plus 2 h recording and edit (Dijo or Gokul).

---

### Item 6 (optional). NEAR Intents so a sponsor can fund a pet's budget from any chain

**Verified facts.** The 1Click API is `POST https://1click.chaindefuser.com/v0/quote` (fields `dry`, `swapType`, `originAsset`, `destinationAsset`, `amount`, `recipient`, `recipientType`, `refundTo`, `refundType`, `depositType`, `slippageTolerance`, `deadline`) and `GET /v0/status?depositAddress=...` (statuses `PENDING_DEPOSIT`, `KNOWN_DEPOSIT_TX`, `PROCESSING`, `SUCCESS`, `INCOMPLETE_DEPOSIT`, `REFUNDED`, `FAILED`). No key is required; unauthenticated quotes carry an extra 0.25% fee (docs.near-intents.org). `GET /v0/tokens` lists assets (Base USDC is `nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near`, NEAR is `nep141:wrap.near`).

**Catch.** 1Click delivers wNEAR (a NEP-141 token), not native NEAR, and a function-call key cannot attach the 1 yocto that `wrap.near.near_withdraw` needs. Kibble solves it with a sponsor account that unwraps (`near_withdraw`, see its `apps/web/lib/guest.ts`). Whether the vault could react to a plain `ft_transfer` is not something to assume (**VERIFY** how 1Click delivers on NEAR before designing around `ft_on_transfer`).

**6a (2 to 3 h).** `apps/server/src/intents.ts` (new) with `GET /intents/quote?chain=base&usd=1&pet=<pet>` that returns a dry-run quote (`dry: true`, `swapType: EXACT_INPUT`, `originAsset` the chosen chain's USDC, `destinationAsset: nep141:wrap.near`, `recipient` the feeder account, `recipientType: DESTINATION_CHAIN`, `depositType: ORIGIN_CHAIN`, `refundTo` the sponsor's address, `refundType: ORIGIN_CHAIN`), wired into `apps/web/app/(app)/pet/page.tsx` or `/me` as "Feed from any chain" with the quote and the status stepper. A dry run sends nothing and costs nothing.
**6b (3 h, only after everything else).** A real swap of about 1 USD with a relay account `feeder.gremlo.near` whose hot full-access key holds a capped float (at most 1 NEAR) and does `near_withdraw` then a new payable `fund_pet(pet_id)` on the vault. This puts a hot full-access key back in the picture: say so plainly in the README and cap the float, or do not ship 6b.

---

### Item 7 (optional). Deepen the TEE verification

Bitty Beasts verifies raw Intel TDX quotes (report data binds the signing address and a fresh nonce, TD debug bit off, `MRCONFIGID` matches `sha256(app_compose)`, GPU evidence carries the nonce); Gremlo's `apps/server/src/verify.ts` states that it does not check the TDX or GPU quotes. Re-implement the nonce and report-data binding checks in `verifyCompletion` (do not copy Bitty's code; read its `docs/TEE-VERIFICATION.md` for what to check). Optionally pass the NEAR AI signature to `charge_compute` and record `env::ecrecover` validity in the event without rejecting (Kibble rejects; Gremlo should only record, because attested signing addresses rotate). 4 to 6 h; skip unless the rest is done.

---
## 4. Milestones

### Priority milestones (what to ship; decided 28 Nov 2026, IST)

These are the product milestones, in order. World ID is not among them (it is off; item 4 is a docs label inside milestone 4).

1. **Milestone 1 — Mainnet + one real flow** (item 1, about 6 to 7 h). A view settles on mainnet and pays for one TEE-signed NEAR AI call. Start **ASAP, immediately after BotFolio ships** (internal done-by 29 Nov, 9 PM IST). Target by 30 Nov. This is the priority. It is executed as commit milestone M4, and only after contract v2 is frozen (see below), because the vault is locked after deploy and cannot be upgraded.
2. **Milestone 2 — Remove the god key** (item 2). The operator gets a function-call key limited to four methods, and the vault is locked (2A, about 5 h). The contract checks the Mac's Secure Enclave signature on-chain with `p256_verify` (2B, 8 to 10 h). Contract work for this milestone is a prerequisite of Milestone 1 and is frozen at gate G1.
3. **Milestone 3 — Per-pet purse** at `<pet>.pets.gremlo.near` (item 3, 3 to 4 h). The contracts are already built and wired; they need deploying.
4. **Milestone 4 — Docs, proof scripts, CI and video** (item 5, 4 to 5 h plus 2 h recording). Includes labelling World ID as off/disabled in README, JUDGE.md and the What's real table.
5. **Milestone 5 — Optional: NEAR Intents** (item 6). Item 7 (TEE depth) stays optional too.

### Commit milestones (one commit per milestone on `mainnet-upgrade`)

Execution still uses this sequence. Contract v2 must be frozen before the one-time mainnet deploy and lock. Priority Milestone 1 is commit milestone M4.

| # | Milestone | Contains | Done when | Est. |
|---|---|---|---|---|
| M0 | Baseline | Branch, `docs/MAINNET_PLAN.md` from plan mode, test baseline, `scripts/mainnet/common.sh`, `prove-keys.ts` skeleton (read-only, works on testnet today) | `npm test` and `cargo test` match the baseline; plan approved by Divesh | 1 h |
| M1 | Contract v2 | Item 2A contract changes; 2B `settle_signed` with `p256_verify` behind `legacy-settle` flag; `paused`; tests; test vectors | `cargo test` and `cargo test --features legacy-settle` green, invariant test green | 5 h (2A 1.5 h + 2B 4 h incl. vectors) |
| M2 | Plumbing | Server changes for owner-signed registration, `settle_signed` batches, DER to raw conversion, health allowance check; web `registerPet` and `add_device`; Mac RPC from server info; network-aware `experience` page. No World ID production work; flags stay off (item 4 is docs, in M5) | All unit tests green; local sandbox end-to-end run passes (`apps/server` e2e) | 4 to 5 h |
| M3 | Testnet rehearsal | Run every `scripts/mainnet/*.sh` with `NETWORK=testnet` on fresh throwaway accounts, including lock, `prove-keys`, `attack-demo --live`, one real Mac view and one real thought | Rehearsal evidence saved under `docs/rehearsal/`; gate G1 passed | 3 h |
| M4 | **Priority Milestone 1: Mainnet + one real flow** | Item 1 steps 2-8 and item 3 steps 2-7, with Divesh at the keyboard for every signature. Starts ASAP after BotFolio ships; target by 30 Nov | Items 1, 2, 3 acceptance criteria hold on mainnet | 5 to 6 h hands-on |
| M5 | Truth and proof | Item 5: docs (including World ID labelled off), fixtures, `verify-public` parameterised, CI, demo capture list, video | Fresh-clone proof run passes; docs reviewed line by line; World ID clearly off in README and JUDGE.md | 5 to 6 h |
| M6 | Optional | Item 6 (Intents), item 7 (TEE depth), `/prove` page | Only if M0 to M5 are done | 3 to 8 h |

Total core (M0 to M5): about **23 to 27 h** of work (World ID production work is out; the 0.5 h label is inside M5), including about 5 to 6 h that only Divesh can do (accounts, signatures, the lock). Recording stays with Dijo or Gokul. Parallelise per section 7.

## 5. Execution order and gates

Order differs from the priority order because contract code must be frozen before the one-time mainnet deploy and lock.

1. **M0** then **M1** (contract v2) first. Everything else depends on it.
2. In parallel with M1: item 5 docs scaffolding, `prove-keys.ts`, `verify-public.ts --fixture`, and the World ID "off / disabled" copy (item 4).
3. **GATE G1, contract freeze** (target: Sat 28 Nov, late night, or Sun 29 Nov 2 PM IST at the latest). Conditions: sandbox tests green; 2B verified against a signature captured from a real Mac. If 2B is not green at the latest freeze time, build with `legacy-settle` on and ship 2B-lite (item 2). After G1, contract code does not change. A bug found later means a new vault account on testnet first.
4. **M2** then **M3** testnet rehearsal. G1 is passed only after the rehearsal's lock step worked.
5. **GATE G2, first mainnet signature.** Divesh reads the dry-run output of `10-create-accounts.sh` and `20-deploy-vault.sh`, the cost table (section 6) and the recorded wasm hash. Claude Code stops and waits.
6. **M4** (Priority Milestone 1) mainnet + one real flow: accounts, deploy, smoke test, operator key, factory, purse creation. Start ASAP after BotFolio ships; target by 30 Nov.
7. **GATE G3, lock.** Divesh types the word `LOCK` in the chat; Claude Code first pastes the output of `get_admin`, `get_operator`, `get_totals`, `list-keys` and the code hash. Only after G3 run the real flow (item 1 step 7) so it happens on the locked contract.
8. **M5** proof, docs, video.
9. **GATE G4, publish.** Divesh reads the README diff; X posts only as approved draft cards.

## 6. Risk and safety

### Keys and who holds what

| Key | Where | Can do | If stolen |
|---|---|---|---|
| `gremlo.near` full-access (admin) | Divesh's macOS keychain or a Ledger; never on a server | Call `set_operator`, `set_paused`, own the parent name | Attacker swaps the operator, but cannot move vault funds or change code. Rotate with `set_operator`. |
| `operator.gremlo.near` full-access | Divesh's keychain, cold | Sweep fees, rotate the function-call key | Lose the fee float (small) |
| Operator function-call key | `/etc/gremlo/mainnet.env` on the EC2 box (root, 600) | Only `settle_signed`, `charge_compute`, `set_verified`, `close` on the vault, gas allowance 2 NEAR | See Appendix C |
| `vault.gremlo.near`, `pets.gremlo.near` | No keys after the lock | Nothing off-contract | n/a |
| Pet owner's wallet key | Owner's wallet | Registers the pet, creates the purse, withdraws | Owner's problem, not the platform's |
| Mac's purse key | Mac Keychain (already) | Only `pay_inference` on the purse, within caps | Drains at most `daily` (0.01 NEAR) per day to the allow-listed provider |
| Mac Secure Enclave key | Secure Enclave, non-exportable | Signs views | Cannot leave the device |
| `NEAR_AI_API_KEY` | Server env only | AI calls | Rotate in the NEAR AI dashboard |
| `RP_SIGNING_KEY` | Testnet server only; unset on mainnet | World signing on the testnet simulator | Not used on mainnet (World ID is off) |

Rules for Claude Code and every teammate: no private key, seed phrase, API key or `.env` content in a commit, a PR, a chat, a log line or a shell command visible in history; use `sudoedit` on the server, `save-to-keychain` locally, `print-to-terminal` only for the one operator function-call key and only into a root-only file. Do not read `.env*`, `~/.near-credentials`, or the keychain. If a command would print a secret, do not run it; ask Divesh.

### Irreversible or externally visible steps (always stop and ask)
Account creation and funding; contract deploy; adding or deleting a key; the lock; any transaction that moves NEAR; DNS or EC2 changes; pushing a branch, opening a PR, posting on X. Each script defaults to a dry run and needs `CONFIRM_MAINNET=yes`. World ID stays off; do not switch on a Developer Portal production app.

### Mainnet cost estimate (NEAR price about 3.05 USD on 28 Nov 2026; recheck)

| Item | NEAR | Notes |
|---|---|---|
| `gremlo.near` creation and gas money | 3 | Account name is free today (checked); keep 1 NEAR spare |
| `vault.gremlo.near` storage stake (wasm size not yet measured; budget 300 KB) | about 3.5 | 1 NEAR per 100 KB, locked while the code is deployed, recoverable only by deleting the account |
| `operator.gremlo.near` balance | 1.5 | Gas for the function-call key (allowance 2 NEAR is a cap, not a deposit) |
| `pets.gremlo.near` factory (258 KB wasm) | about 3 | Storage stake plus a little gas |
| `brand.gremlo.near` | 0.5 + campaign | Campaign deposit 0.2 NEAR |
| One pet's purse | 2 | Created by the owner |
| Vault compute budget flow | under 0.01 | Funded from the campaign |
| Gas for all deploys and calls | under 0.3 NEAR burnt | |
| **Total locked or spent peak** | **about 12 NEAR (about 37 USD)** | Most is a refundable stake, true burn is under 0.3 NEAR |

Skipping `pets.gremlo.near` (deploy the purse straight to the pet's account) saves about 3 NEAR. NEAR AI credit usage is separate (a few cents).

### Failure modes and rollbacks
- **Wrong vault code deployed before the lock:** redeploy from the admin key; this is why the lock is the last step before the real flow.
- **Bug after the lock:** cannot patch. Deploy a new vault account, announce it, keep the old one's history. Rehearsal (M3) exists to make this unlikely.
- **Operator allowance exhausted:** the function-call key can no longer sign; `/health` warns at 0.2 NEAR; add a new key with the operator's full-access key and rotate the env var.
- **Operator compromised:** `set_paused(true)` (admin), delete the key, `set_operator` to a fresh account. Impact is bounded by Appendix C.
- **Settle fails with `p256_verify` gas:** lower the batch size; the call is idempotent per report because of the `time_ms` guard.
- **RPC rate limit:** failover list in `chain.ts`.
- **Testnet submission:** never touched. Mainnet runs on a second instance and a second Vercel project; the old tag stays.

## 7. Timeline and owners (fits around BotFolio)

BotFolio's internal done-by is **29 Nov, 9 PM IST** and it has priority until then. Today is Sat 28 Nov (IST). **Priority Milestone 1 (mainnet + one real flow) starts ASAP, immediately after BotFolio ships, target by 30 Nov.** That replaces the earlier "Mon 30 Nov morning" slot. If BotFolio slips, drop to the minimum set at the bottom.

| Slot (IST) | Who | Work |
|---|---|---|
| Sat 28 Nov evening, 2 h | Divesh with Claude Code | M0, then contract v2 (commit M1) in plan mode, one approval of the plan |
| Sat 28 Nov night, 2 to 3 h (async) | Claude Code alone on the branch | Contract v2 to a G1 candidate; Dijo or Gokul reviews the test list in the morning |
| Sun 29 Nov morning | Divesh 1 h, Claude Code | M2 plumbing (World ID stays off; no noon decision) |
| Sun 29 Nov noon to about 3 PM | Divesh 1 h, Claude Code | M3 testnet rehearsal, G1 |
| Sun 29 Nov afternoon to 9 PM | **BotFolio** | Gremlo paused (start time assumed; adjust) |
| **ASAP after BotFolio ships (Sun 29 after 9 PM IST), target by 30 Nov** | Divesh with Claude Code | G2, M4 mainnet deploy, G3 lock, one real flow (Priority Milestone 1). Do not wait for Monday morning |
| After the real flow, still targeting 30 Nov | Claude Code and Divesh | M5 docs and proof, including World ID labelled off; capture assets |
| 30 Nov evening / Tue 1 Dec | Gokul or Dijo | Record and edit the video; Divesh approves the X draft |

Do not wait for a Monday-morning slot. Start the mainnet deploy as soon as BotFolio ships. Target: one real flow done by 30 Nov. If a still-earlier Sunday deploy is forced (during BotFolio hours), the only way to fit it is the v2-lite path (2A + 2B-lite, no on-chain signature verification) and skipping M3's full rehearsal; say so in the docs.

**Suggested splits** (each in its own git worktree, with `claude --worktree` or `git worktree add`):
- **Dijo:** item 5 docs and the video (README, JUDGE.md, SECURITY.md, TRUST.md, World ID labelled off, capture checklist, edit). Needs no keys.
- **Gokul:** `prove-keys.ts`, `attack-demo.ts`, `verify-public.ts --fixture`, the `/prove` page, CI changes. Needs no keys (read-only plus testnet).
- **Divesh with Claude Code:** contract v2, deploy and lock, everything that signs.
- **Nobody** touches contract code after G1 or any key.

Minimum if time is short (about 9 h): M0, 2A (function-call key and lock) + 2B-lite, item 1 flow on mainnet, README refresh with World ID labelled off. Skip 2B, items 3 (keep it as built and tested, state "not deployed"), 6, 7.

## 8. Patterns to borrow (read, do not copy code)

**Kibble** (`github.com/isaacessuman/kibble`, a pet-and-arena app, NEAR mainnet):
- `docs/ATTACK-DEMO.md`: a scripted "try to rob it" run with the actual refusals and tx links; model for item 2's `attack-demo.ts`.
- `ecrecover` check in the pets contract at charge time: a signature check on-chain, rejects invalid; Gremlo copies the idea in `settle_signed` with `p256_verify`.
- 1Click feed (`apps/web/lib/intents-adopt.ts`, `guest.ts`): a sponsor funds from any chain; model for item 6 and its wNEAR caveat.
- The judge path is one browser page that proves things without keys; model for `/prove`.

**Bitty Beasts** (`github.com/mudl-world/bittybeasts`, a Tamagotchi-style pet on NEAR testnet that still made the shortlist; so mainnet alone does not decide it):
- `scripts/lock-alley.ts`: a script that deletes the keys and lists what is left; model for `50-lock.sh` and `prove-keys.ts`.
- `contracts/alley` with `use_global_contract_by_account_id`: how a global contract is published and used (scale path for purses, 10 NEAR per 100 KB burned).
- `docs/TEE-VERIFICATION.md`: what a real TDX quote check covers; model for item 7.
- Evidence-first docs: a table of claim, command, expected output.

## 9. Definition of Done

- [ ] Branch `mainnet-upgrade` exists with one commit per milestone; nothing pushed unless Divesh pushed it; no secrets in history (`git log -p | rg -i "ed25519:|nearai_|sk-"` returns nothing sensitive).
- [ ] Vault, factory and one purse deployed on mainnet; code hashes recorded in `fixtures/public-proof.mainnet.json`.
- [ ] `vault.gremlo.near` and `pets.gremlo.near` have no keys (`list-keys` output pasted in PROOF.md).
- [ ] The operator on the server holds only a function-call key restricted to the four methods; `prove:keys` prints PASS for every claim.
- [ ] One real mainnet view settled by `settle_signed` (or `settle_impressions` with a log anchor in the lite path), one real `compute_charged` with a TEE completion id verified SIGNED; both links in README, JUDGE.md, PROOF.md.
- [ ] Per-pet purse paid one thought on mainnet; the Mac key cannot call anything else.
- [ ] World ID is labelled honestly as off/disabled in README.md, JUDGE.md and the What's real table; flags stay at their defaults (off); no production World app; no pet presented as a verified human.
- [ ] `docs/TRUST.md` and `docs/ATTACK-DEMO.md` exist and match the live key lists.
- [ ] `npm run verify:public` passes for both testnet and mainnet fixtures from a fresh clone, CI green.
- [ ] `npm test` (server, web, brain), `cargo test` (vault, factory, purse) pass.
- [ ] README, JUDGE.md and SECURITY.md contain no claim that a command does not support; no "self-funded", no earning claims.
- [ ] The testnet submission is intact (tag, live API, vault).
- [ ] Video of 30 to 45 s recorded from real mainnet footage; X post drafted as a card for Divesh's approval.
- [ ] Time actually spent and anything cut recorded in `docs/MAINNET_PLAN.md`.

---

## Appendix A. Runbook commands (near-cli-rs 0.31.1 syntax, validated with `--help`; replace names)

```bash
# install the CLI (official installer; once)
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/near/near-cli-rs/releases/latest/download/near-cli-rs-installer.sh | sh

# 0. read-only: confirm names are free (expect an error that the account does not exist)
near account view-account-summary gremlo.near network-config mainnet now

# 1. create the top-level account from Divesh's funded wallet
near account create-account fund-myself gremlo.near '3 NEAR' autogenerate-new-keypair save-to-keychain sign-as <DIVESH>.near network-config mainnet sign-with-keychain send
#    sub-accounts (parent signs)
near account create-account fund-myself vault.gremlo.near '4 NEAR' autogenerate-new-keypair save-to-keychain sign-as gremlo.near network-config mainnet sign-with-keychain send
near account create-account fund-myself operator.gremlo.near '2 NEAR' autogenerate-new-keypair save-to-keychain sign-as gremlo.near network-config mainnet sign-with-keychain send
near account create-account fund-myself pets.gremlo.near '4 NEAR' autogenerate-new-keypair save-to-keychain sign-as gremlo.near network-config mainnet sign-with-keychain send
near account create-account fund-myself brand.gremlo.near '1 NEAR' autogenerate-new-keypair save-to-keychain sign-as gremlo.near network-config mainnet sign-with-keychain send

# 2. deploy and initialise the vault in one transaction
near contract deploy vault.gremlo.near use-file contracts-near/target/near/campaign_vault.wasm with-init-call new json-args '{"admin":"gremlo.near","operator":"operator.gremlo.near"}' prepaid-gas '30 Tgas' attached-deposit '0 NEAR' network-config mainnet sign-with-keychain send

# 3. the operator's restricted key (private key printed once, goes into the root-only env file)
near account add-key operator.gremlo.near grant-function-call-access --allowance '2 NEAR' --contract-account-id vault.gremlo.near --function-names 'settle_signed,charge_compute,set_verified,close' autogenerate-new-keypair print-to-terminal network-config mainnet sign-with-keychain send

# 4. lock: list, then delete every key on the vault and factory accounts
near account list-keys vault.gremlo.near network-config mainnet now
near account delete-keys vault.gremlo.near public-keys ed25519:<KEY> network-config mainnet sign-with-keychain send

# 5. prove
near account list-keys vault.gremlo.near network-config mainnet now
near contract inspect vault.gremlo.near network-config mainnet now
near contract call-function as-read-only vault.gremlo.near get_totals json-args '{}' network-config mainnet now
```

Checks before relying on a form: run `near <subcommand> --help`; the vault wasm path `contracts-near/target/near/campaign_vault.wasm` is where `cargo near build` writes it (**VERIFY** after the build); the minimum for a new top-level account may be higher than shown (the CLI prints the error); a name like `gremlo.near` may be taken by the time of the run (use `gremlo-pet.near` and update all names). Facts checked against docs.near.org on 28 Nov 2026: function-call keys carry a receiver, optional method list and allowance and cannot attach a deposit or transfer NEAR; an account with no keys is locked; only a parent account creates sub-accounts.

## Appendix B. Environment matrix

| Name | Where | Testnet submission (today) | Mainnet instance |
|---|---|---|---|
| `NEAR_NETWORK` | server, web (`NEXT_PUBLIC_NEAR_NETWORK`) | `testnet` | `mainnet` |
| `NEAR_CONTRACT_ID` | server | `vault.gremlo.testnet` | `vault.gremlo.near` |
| `NEAR_OPERATOR_ACCOUNT_ID` | server | testnet operator | `operator.gremlo.near` |
| `NEAR_OPERATOR_PRIVATE_KEY` | server (secret) | full-access key | function-call key |
| `PURSE_PARENT` | server | `pets.gremlo.testnet` if set | `pets.gremlo.near` |
| `NEXT_PUBLIC_WORLD_ENV`, `_APP_ID`, `_RP_ID`, `_PRESET` | web | `staging` (simulator, testnet submission) | unset / off. Do not set production |
| `RP_SIGNING_KEY`, `WORLD_APP_ID`, `RP_ID` | server | staging app (testnet) | unset on the mainnet instance. World ID is off |
| `HOLDBACK_HOURS` | server | 24 | 0 for the demo, then 1 |
| `GREMLO_SERVER`, `GREMLO_WEB`, `NEAR_RPC` | Mac | testnet hosts | mainnet hosts |
| `NEAR_AI_API_KEY` | server (secret), verify script | same | same |

Names that are exactly as in the repo's `.env.example` files: **VERIFY** each before use. Do not add `WORLD_MODE` or production World vars; World ID stays off.

## Appendix C. What each key can do (goes into `docs/TRUST.md`)

| If this is compromised | Worst case | What stops it |
|---|---|---|
| Operator function-call key | Call `settle_signed` with garbage (contract rejects: signature, device, replay, caps), `charge_compute` up to each pet's `compute_budget` and daily cap (it pays the operator's own account the fee, so it can only move already-earmarked compute budget to the operator), `set_verified(true)` for a pet it controls, `close` a campaign (refunds the brand) | No withdraw, no admin methods, no deposits, allowance 2 NEAR |
| Admin key | Swap the operator, pause | Cannot touch funds or code |
| Server box | Same as the operator key, plus the log and store files | Funds are in the contract; the log is hash-chained and public |
| Mac with a modified app | Fake presence signals for its own pet within daily caps (120 views a day) | Caps; the 24 h holdback in the testnet instance; fraud scoring in `fraud.ts` |
| Pet owner's wallet | The owner's pet and purse | Platform funds unaffected |

Not guarded against, say so plainly in `docs/TRUST.md`: the operator can still refuse to settle (liveness); World ID is off, so do not describe `set_verified` as a human check, and do not use it on mainnet (if the method remains, a malicious operator could still flip the flag); a bug in the immutable contract cannot be patched.

## Appendix D. Contract v2 interface sketch (not final code; keep names stable for the Rust and TypeScript tests)

```rust
// contracts-near/src/lib.rs
#[near(serializers=[json])]
pub struct SignedReport {
    pub device_key: Base64VecU8, // 33 bytes, compressed SEC1
    pub time_ms: u64,
    pub body: String,            // the exact JSON body the Mac signed
    pub sig: Base64VecU8,        // 64 bytes, r || s
    pub accepted: u32,           // rows the server counted; the contract takes the minimum
}

pub fn register_pet(&mut self, pet_id: String, payout: AccountId);          // payable, owner = predecessor
pub fn set_verified(&mut self, pet_id: String, verified: bool);             // operator
pub fn add_device(&mut self, pet_id: String, device_key: Base64VecU8);      // payable, owner
pub fn remove_device(&mut self, pet_id: String, device_key: Base64VecU8);   // owner
pub fn settle_signed(&mut self, id: u64, pet_id: String, reports: Vec<SignedReport>) -> u64; // operator
pub fn charge_compute(&mut self, pet_id: String, cost: U128, request_id: String) -> U128;    // operator (existing)
pub fn set_paused(&mut self, paused: bool);                                  // admin
pub fn version(&self) -> String;

// digest the contract recomputes (verified against the Mac's existing signing code in main.swift `deviceSign`)
// message = format!("POST\n/impressions\n{}\n{}", time_ms, hex(sha256(body)))
// digest  = env::sha256_array(message.as_bytes());            // the Mac signs with SHA-256 inside CryptoKit
// ok      = env::p256_verify(&sig, &digest, &device_key);     // NEP-635, ~1.3 Tgas base
```
Test with: a signature produced by Node `crypto` with `dsaEncoding: "ieee-p1363"` on the same message; the (r, n-s) twin signature (both verify; the `time_ms` guard is the replay defence); a body whose JSON key order differs (must still parse); the captured Mac signature from the testnet rehearsal.

## Appendix E. Sources checked (28 Nov 2026)

- NEAR docs: access keys (function-call keys and limits), CLI, global contracts (NEP-591 cost), accounts and sub-accounts, `p256_verify` host function (NEP-635) and near-sdk 5.30.1 `env::p256_verify`.
- NEAR Intents 1Click: `docs.near-intents.org` (quote, status, tokens, 0.25% unauthenticated fee).
- World ID: Developer Portal and IDKit v4 docs were checked only as background. World ID is completely off for this upgrade; no production setup.
- NEAR AI Cloud docs (OpenAI-compatible API, TEE signatures, credits).
- Repos: `DiveshK007/GREMLO`, `isaacessuman/kibble`, `mudl-world/bittybeasts`.
- Live on-chain checks: key lists for the testnet vault and operator, protocol 88 `p256_verify` costs, name availability on mainnet, NEAR price.
