# Mainnet plan (M0)

Written 28 Nov 2026 (IST) from `docs/MAINNET_UPGRADE_SPEC.md` (the spec), read against `main` at `71bdada`.
Status: waiting for Divesh's approval. Nothing below has been run. No code is changed until the plan is approved.

Decisions carried from the spec, not reopened:
- World ID stays off. The existing integration stays in the repo, unused on mainnet. The only World ID work is to say so in README, JUDGE.md, the What's real table and the copy that claims a human check (M5), plus the code that lets the server and `/pet` run without World env (M2, see contradiction 10).
- Priority Milestone 1 (mainnet + one real flow) runs as commit milestone M4, after contract v2 is frozen.
- Copy rule from spec decision 4 applies to every line written: the purse and the loop are described as "paid from the pet's own account" or "paid from what it earned", never as needing no top-up.
- Stop and ask before anything that signs on mainnet, spends NEAR, creates or deletes an account or key, deploys, locks, changes EC2 or Vercel, pushes, or posts.

## 1. Decisions needed before M1 starts

Each has a default. Say "defaults" to take all of them.

| # | Question | Default | Why |
|---|---|---|---|
| D1 | With World ID off, what does `verified` mean? `settle_impressions` requires it, the spec keeps `set_verified` on the operator key, and item 4 / Appendix C say not to use it on mainnet. | `settle_signed` does not check `verified`. The mainnet operator key gets three methods: `settle_signed, charge_compute, close`. The field and `set_verified` stay in the contract (no deletion), documented as unused on mainnet. | Only the operator can call `settle_signed`, and it already chooses which reports to send (fraud rules, caps). A second operator-set flag adds no protection and is one more thing a stolen key can flip. |
| D2 | Replay guard. The spec keeps one `last_time_ms` per device. The Mac reports each campaign separately, so with two live campaigns (testnet has 3) settling campaign A first makes campaign B's older reports fail forever. | Keep a high-water mark per (device, campaign): each `Device` holds 4 fixed slots `(campaign_id, last_time_ms)` plus `floor_ms`. A campaign not in the slots must beat `floor_ms`; evicting a slot raises `floor_ms` to its time. | Bounded storage paid once at `add_device`, never grows during settlement. Errs toward not paying, never toward paying twice. |
| D3 | A bad report in a batch: panic the whole tx (spec) or skip it? | Skip: `settle_signed(...) -> Vec<u32>`, one count per report, 0 with a reason in the event. Panic only on call-level errors (`NotOperator`, `Paused`, `UnknownCampaign`, `CampaignEnded`, `OverBudget`, more than 20 reports). | With panics, one stale report blocks a pet's settlement until the server guesses which one; every retry burns allowance. |
| D4 | Device key format on chain. | `add_device` and `SignedReport.device_key` take the 65-byte X9.63 key the Mac already sends everywhere; the contract compresses it (3 lines) and stores 33 bytes. | No `compressP256` in the server or the web. Names in Appendix D stay. |
| D5 | Where the mainnet API code comes from. The EC2 box auto-deploys `main` into `/opt/gremlo` for `apps/server` and `packages/brain`. | Mainnet instance runs from its own checkout `/opt/gremlo-mainnet` at a pinned `mainnet-upgrade` commit, no auto-deploy. `mainnet-upgrade` is not merged to `main` until after M5 (then decide: dual path or retire testnet). | v2 server code against the v1 testnet vault breaks the live API (it would call `settle_signed`, which `vault.gremlo.testnet` does not have). |
| D6 | Branch policy. CLAUDE.md says merge to main often; spec rule 2 says never push to main. | Spec rule 2 wins for this branch. Getting the code to EC2 and Vercel needs the branch pushed: that is a stop-and-ask step in M4. | |
| D7 | The spec's M2 gate "local sandbox end-to-end run passes (`apps/server` e2e)". No such test exists. | Drop it. Unit tests plus the M3 testnet rehearsal (a real Mac, a real wallet, a real server) are the end-to-end check. | Building a sandbox e2e harness is 3 h for a check M3 does for real. |
| D8 | Rehearsal accounts. | A fresh faucet-funded testnet root (for example `gremlo-r1.testnet`, plus one owner account), not sub-accounts of `gremlo.testnet`. | Keeps the submission accounts' history untouched. If the faucet gives too little, fall back to `vault2.gremlo.testnet` signed by `gremlo.testnet`. |

## 2. Where the repo contradicts the spec

Checked file by file on 28 Nov against `71bdada`. "Spec" means `docs/MAINNET_UPGRADE_SPEC.md`.

**Already fixed or moved since the spec was read (b53a571)**

1. README dmg link (spec 1.1 item 8): fixed by `36d61d7`. README line 82 now links `v1.0.2/Gremlo-1.0.2.dmg` with its sha256. Drop it from M5.
2. `apps/server/src/routes/settle.ts` changed in `36d61d7`: `settle(id)` keeps going after a failing pet and stops only on an unconfirmed tx (line 79); it pre-checks that the payout account exists (57) and that `pet.verified` is true (61, with the World-specific message "register it again on the web"); failures go to `settleErrors` (`state.ts` 211). The 2B rewrite keeps all three; the verified check follows D1.
3. `apps/server/src/routes/pets.ts` `getPet` now returns `thisDevicePaired` (from `?device=`, line 211) and `views` with `settleError` (212-217). 2B adds an on-chain device flag next to these.

**Line numbers and names that moved**

4. `contracts-near/src/lib.rs` is 467 lines (contract to 333, three unit tests after), not 341. Integration tests in `tests/vault.rs` are 19, not 18 (README line 195 also says 18). `assert_invariant` line 85, `register_pet_operator_only_once_with_storage` line 152 and `random_operations_keep_the_invariant` line 388 are correct.
5. `charge_compute` is `charge_compute(pet_id, amount: U128, near_ai_completion_id: String)` and returns nothing (lib.rs 247). Appendix D shows `(pet_id, cost, request_id) -> U128`. Keep the real signature: the server, the event field `near_ai_completion_id` and the proof scripts use it.
6. `pets.ts`: `PET_STORAGE_DEPOSIT` is line 49 (spec 48); `registerPet = makeRegister` is 66-79 (spec 64-77); `send("register_pet")` is line 72; `purseOf` 364, `purseGate` 384, `bill` 391, `pursePaid` 407 (spec 355/382/398); `explorer` is returned at line 251 (spec "about 242").
7. `HOLDBACK_HOURS` is `state.ts` line 216 (spec 214). `close` is sent by `workerPass()` (settle.ts 138), not by `settle(id)`.
8. Mac: the purse RPC default is `Purse+Mac.swift` line 13 (spec 14); the explorer fallback is `Backend+Mac.swift` line 632 (spec 596). `Models+Mac.swift` line 19 and `Phone+Mac.swift` 133-134 are correct.
9. `/health`'s 0.5 NEAR rule is `OPERATOR_LOW` in `apps/server/src/health.ts` (the pure `health()`), fed by `apps/server/src/routes/health.ts`. The allowance check goes in both.

**Facts in the spec that are wrong for this repo**

10. The server cannot start without World env. `state.ts` 135-137 throws `missing env RP_ID or RP_SIGNING_KEY`. `makeRegister` requires `worldProof` and a nullifier (register.ts 122-134). `/pet`'s `validate()` fails with "World app ID / RP ID missing" (pet/page.tsx 96), and the whole page is World ID copy. There is no flag "defaulting off": `WORLD_ENV` defaults to `staging` (`apps/web/lib/config.ts` 10). So World ID off needs code in M2 (about 1.5 h), derived from empty `RP_ID` / `NEXT_PUBLIC_WORLD_APP_ID`, with no new `WORLD_MODE` variable (Appendix B forbids one).
11. The Mac's purse RPC variable is `GREMLO_NEAR_RPC`, not `NEAR_RPC`: `Legacy.env` prefixes `GREMLO_` (GremloCore/Legacy.swift 9-11; HANDOFF line 77). Spec item 1 step 7a and Appendix B set `NEAR_RPC`, which does nothing; purse payments would go to testnet RPC.
12. `send()` in `chain.ts` (line 93) attaches 100 Tgas to every call. A 20-report `settle_signed` (spec: up to 300 Tgas) needs a gas argument. With a function-call key, prepaid gas is charged to the key's allowance; at the minimum gas price 100 Tgas is about 0.01 NEAR, so a 2 NEAR allowance lasts roughly 200 calls if unused gas does not return to the allowance (**VERIFY** in M3 by reading the key's allowance before and after one call). Size gas per method.
13. There is no `apps/server` e2e (scripts: `start`, `test`, `verify`, `verify:public`, `typecheck`). The comment at register.ts 65 points at an Anvil e2e from the 0G build. See D7.
14. `verify-public.ts` reads a fixed fixture path (line 6) and hard-codes `https://test.rpc.fastnear.com` at lines 48 and 57 (as the spec says), but the fixture has no `rpcLive` field. Add it to both fixtures.
15. `.claude/settings.json` denies `Read(./.env)` and `Read(./.env.*)`, anchored at the repo root, plus `**/*.pem` and `**/*.key`. That may not cover `apps/server/.env` or `apps/web/.env`. **VERIFY**; if not covered, Divesh adds `Read(./**/.env)` and `Read(./**/.env.*)`. (A teammate session reading those would break rule 3.)
16. Spec Appendix A creates `gremlo.near` with 3 NEAR, then has it fund 4 + 2 + 4 + 1 = 11 NEAR of sub-accounts. It needs about 14 NEAR. The section 6 cost rows add up to about 14 NEAR, not the stated 12. Peak out of Divesh's wallets: about 14 NEAR plus the owner's 2 NEAR purse deposit, about 16 NEAR (about 49 USD at 3.05). Most is storage stake; true burn stays under 0.3 NEAR.
17. The spec's mainnet unit is "a copy of `gremlo-api.service`", which keeps `WorkingDirectory=/opt/gremlo/apps/server` (the auto-deploy target) and `ReadWritePaths=/data/gremlo`. It needs `/opt/gremlo-mainnet/apps/server` and `ReadWritePaths=/data/gremlo-mainnet` (D5). The EC2 auto-deploy itself is not in the repo (not in `deploy/vm/` or the workflows), and `deploy/vm/Caddyfile` is the `api.example.com` template, so both are box-side changes Divesh makes.
18. Spec 2B test "sign with Node `crypto` ieee-p1363 and compare with `derToRaw` of the DER form": ECDSA signatures are randomized, so two signatures never match byte for byte. The test signs once in DER, converts, and verifies the raw form with `dsaEncoding: "ieee-p1363"`.
19. The spec says 2B needs no Mac change. True for signing. But the popover Health section (`eee1f8f`) shows "paired" from the server; under 2B a Mac paired on the server but not added on chain gets views counted that never settle. `GET /pets/:name` must say whether this device is on chain, and `/me` or the popover must show it.
20. `apps/web/app/(app)/pair/page.tsx` line 104 says "No transaction, no fee". False once pairing includes `add_device`.
21. Factory placement: `contracts-accounts/factory/src/lib.rs` line 1 and `contracts-accounts/README.md` (lines 18-42) say the factory runs on `gremlo.near` / `gremlo.testnet`. The code uses `env::current_account_id()`, so `pets.gremlo.near` works; only the docs change.
22. Copy that claims a human check, beyond README and JUDGE.md: `experience/page.tsx` 24, 54, 243; `money/page.tsx` 115 ("one human each"); `live/page.tsx` 145 ("Verified pets"); `apps/server/src/mail.ts` 47 (brand weekly email: "verified humans"); `pet/page.tsx` 161-163, 266, 291-293. The hard-coded "testnet" lines in `experience/page.tsx` are as the spec lists (case-insensitive) plus 488.
23. Team and committers: README "Team: solo", SECURITY.md "This is a solo project", HANDOFF "One committer", against spec section 7 (Dijo and Gokul commit in worktrees). Either they send patches that Divesh commits, or those lines change in M5.

**Confirmed as the spec says** (no action): near-sdk `=5.30.1` has `env::p256_verify(&[u8; 64], &[u8; 32], &[u8; 33]) -> bool`, not feature-gated for wasm, accepting both `(r, s)` and `(r, n-s)` (checked in the local cargo registry source). `register_pet` is `#[payable]` and operator-only. Purse wasm sizes 258,641 and 128,249 bytes; 14 tests (4 factory, 10 purse); Mac key allowance 0.25 NEAR. `docs/DEPLOY.md` line 5 is stale (and the doc describes Oracle and Google VMs while the API runs on AWS EC2). `docs/WORLD_DEBRIEF.md` line 14 links a 0G chainscan tx. README lines 43 and 151 and PROOF.md say the code hash matches a local build; true for tag `hackathon-submission`, not for `main` once v2 lands.

## 3. Spec design gaps found while planning

Not contradictions with the repo; things the spec's design gets wrong or leaves open. Fixes are inside the milestone estimates below.

- **Replay guard across campaigns**: D2.
- **Daily cap ordering.** "Reject a report whose day is before `pet.view_day`" breaks the same way as D2 when campaigns settle out of order. Use an 8-slot ring on `Pet` indexed by `utc_day % 8` (`(day, count)`), matching the 7-day maximum report age. A slot holding an older day is reset; a slot holding a newer day means the report is too old (count 0).
- **Settlement must not grow storage.** The vault pays storage from its own balance, which is what it owes brands and pets (`assert_invariant` checks `balance >= remaining + compute_budgets`). All per-device and per-day state is allocated at fixed size in `register_pet` and `add_device`, paid by the owner's deposit.
- **Pet names.** Owners now call `register_pet` directly, so the contract's `valid_pet_id` (2-64 chars, `_` and `.` allowed) must match the server and factory rule `PET_NAME` (2-24 of `a-z0-9-`, no dash at either end, register.ts 40). Otherwise a pet can exist on chain that the server and the purse factory refuse.
- **Counted views to log entries.** Today `hold()` buckets by (pet, hour, network) and keeps no entry ids, and `addImpressions` appends to the log after the hold loop. 2B needs each held bucket to carry the log entry indices behind it, so the append moves before `hold()`.
- **`legacy-settle` tests.** `near_workspaces::compile_project("./")` builds without features. Keep the old `settle_impressions` tests behind `#[cfg(feature = "legacy-settle")]` and run them only if the 2B-lite fallback is chosen at G1 (**VERIFY** how to pass features to the build then).
- **`charge_compute` old-id dedupe** (spec 1.1 item 9). Only the operator can call it, and it can charge any fresh id anyway, so a rolling window adds no protection. Leave the code; state it in `docs/TRUST.md`.
- **Public settle route.** `POST /settle/:id` (settle.ts 21) lets anyone trigger a settlement paid with operator gas. Rate limits exist (20 an hour per address, 60 s per campaign). With a function-call key that is allowance; the `/health` allowance check covers it.
- **Item 3 step 6** mentions the World nullifier as the reason for one pet. With World ID off there is none; one demo pet is still the plan.

## 4. Conflicts with the Phase 1 work on main

Phase 1 (Developer ID signing and notarization in `scripts/release-mac.sh` and `.github/workflows/release.yml`, Sparkle, Mac onboarding, opt-in `POST /diagnostics`, polish) is running on `main` now. `apps/mac/Package.swift` already has an uncommitted Sparkle change in the main working tree.

1. **Server changes on main go live on the testnet API.** The EC2 box auto-deploys `main` about 2 minutes after a push that touches `apps/server` or `packages/brain`. `POST /diagnostics` therefore changes the API that judges' `verify:public` and the submission point at, which spec rule 5 says not to touch. Rule 5 binds the mainnet session; Phase 1 is Divesh's call. If it ships, keep it additive: no change to `/stats`, `/health`, `/campaigns/:id/log` or `/pets/:name`.
2. **Mainnet server code must stay off main** (D5). The same auto-deploy would put v2 settlement and owner-signed registration on the testnet API, against the v1 vault.
3. **Same box, two instances.** The mainnet unit must not use `/opt/gremlo` (contradiction 17). Phase 1 deploys restart `gremlo-api` only; the mainnet instance is restarted by hand.
4. **Vercel.** `gremlo.vercel.app` builds `main`, so Phase 1 web polish lands there. The mainnet Vercel project builds `mainnet-upgrade` (needs the branch pushed, stop-and-ask). Phase 1 polish on `/pet` or `/pair` will collide with M2's changes to the same two pages: land Phase 1's first and rebase.
5. **Docs.** Phase 1 rewrites README lines 79-83 (download: notarized dmg, no Open Anyway), `docs/DEPLOY.md` lines 141-146 and 180-193 (signing, "no auto-update yet"), CHANGELOG and probably HANDOFF env names. M5 rewrites README 31, 38-45, 122-168 and 218, JUDGE.md, SECURITY.md, `DEPLOY.md` line 5 plus a new mainnet section. M5 docs go last, rebased on `main` after Phase 1's docs land.
6. **Mac.** Phase 1 touches `Package.swift`, onboarding and Settings. M2's Mac changes (`Purse+Mac.swift`, `Models+Mac.swift`, `Phone+Mac.swift`) are optional for M4: Divesh's demo Mac can use `GREMLO_NEAR_RPC` (contradiction 11). The RPC-from-server change is backward compatible and can go to `main` later. Phase 1 onboarding copy must not promise a human check on mainnet.
7. **Re-signing and the keychain.** The Mac's purse key is a Keychain item (`dev.gremlo.purse`); moving from an ad hoc build to a Developer ID build changes the code signature its access list may check (**VERIFY**). The Secure Enclave device key blob lives in UserDefaults, so it should survive if the bundle id stays (**VERIFY**). If the device key changes, `add_device` and pairing are repeated (0.005 NEAR). Do M3 and M4 on one build of the app, and turn Sparkle updates off on the demo Mac until the recording is done.
8. **CI.** Phase 1 changes `release.yml`; M5 changes `ci.yml` (`proof` job). No file overlap. The `proof` job reads the live testnet API, so a Phase 1 deploy can turn it red for a few minutes.
9. **Working tree.** Do not create `mainnet-upgrade` with `git checkout -b` in `/Users/bond/GREMLO`: it would carry Phase 1's uncommitted `Package.swift`. Use a worktree (M0).

## 5. Milestones

Hours are Claude Code assisted. "Divesh" means he must be at the keyboard. "NEAR" means real mainnet NEAR.

### M0. Baseline (1 h, no NEAR)

- `git worktree add ../gremlo-mainnet -b mainnet-upgrade main`, then copy `docs/MAINNET_UPGRADE_SPEC.md` (untracked) and this file into it.
- Record the test baseline in this file (section 8): `cargo test` in `contracts-near` and `contracts-accounts`; `npm ci && npm test && npm run typecheck` in `apps/server`; `npm test` in `packages/brain`; `npm run typecheck && npm test` in `apps/web` (build in a `/tmp` copy, per HANDOFF); `swift build && swift test` in a `/tmp` copy of `apps/mac`. README says 79 / 16 / 4 / 114 / 3+18 (19 in fact) / 14.
- New `scripts/mainnet/common.sh`: reads `NETWORK` (`testnet` or `mainnet`) and `ROOT` (`gremlo.near`, or the rehearsal root); `run` prints the command and the NEAR it moves, and executes only on testnet or with `CONFIRM_MAINNET=yes`. Self-check: `bash scripts/mainnet/common.sh --selftest` asserts that mainnet without the confirm variable prints and does not execute.
- New `apps/server/scripts/prove-keys.ts` skeleton (`npm run prove:keys -- --fixture <path>`): `view_access_key_list` and `view_account` over plain JSON-RPC, no env. Against the testnet fixture today it must print FAIL for `vault.gremlo.testnet` (it holds a full-access key). That FAIL is the expected result.
- `apps/server/package.json`: `prove:keys`.
- Divesh: approve this plan and answer D1-D8 (15 min).
- Commit: `Mainnet plan, test baseline, mainnet script guard, prove-keys skeleton`.

### M1. Contract v2 (6 to 7 h, no NEAR)

Files: `contracts-near/src/lib.rs`, `contracts-near/Cargo.toml`, `contracts-near/tests/vault.rs`.

- First 30 min, spike: one sandbox test that calls `env::p256_verify` on the doc example vector. near-workspaces 0.24.0 runs near-sandbox 0.4.0 with nearcore 2.14.0 by default; if that node lacks the host function, point `NEAR_SANDBOX_BIN_PATH` at a newer sandbox or bump near-workspaces. Same check for unit tests (near-vm-runner 0.38.1). If neither works, stop: 2B goes to 2B-lite (spec item 2B-lite) and the plan is re-estimated.
- `Vault`: add `paused: bool`. `Pet`: add `devices: Vec<Device>` (at most 5) and `view_days: [(u32, u32); 8]`; drop the `last_charge_key` raw key in favour of a `last_charge` field (fresh deploy, no migration).
- `register_pet(pet_id, payout)`: owner is `env::predecessor_account_id()`, no `only_operator()`, `owner` argument removed, storage-from-deposit and refund kept. `valid_pet_id` tightened to the `PET_NAME` rule.
- `add_device(pet_id, device_key)` (payable, owner only, 65-byte X9.63 per D4, stored compressed with 4 campaign slots and `floor_ms`), `remove_device(pet_id, device_key)` (owner).
- `settle_signed(id, pet_id, reports: Vec<SignedReport>) -> Vec<u32>` (operator, not paused, at most 20). Per report, ascending `time_ms`: device registered on the pet; high-water mark per D2; `time_ms` at most 5 min ahead of block time, at most 7 days old, `time_ms / 1000 <= end_time`; message `POST\n/impressions\n{time_ms}\n{hex(sha256(body))}`, `p256_verify(sig, sha256(message), key)`; parse `body` with `near_sdk::serde_json`, count rows with `petKey == pet_id`, `campaignId == id` (string or number), `unlocked && visible && shownMs >= 5000 && idleS <= 300`; `n = min(count, accepted)`; day cap 120 on the ring. Totals go through one internal `pay_views(id, pet_id, count)` extracted from `settle_impressions`. No `verified` check (D1).
- `settle_impressions` behind `#[cfg(feature = "legacy-settle")]`; `[features] legacy-settle = []` in Cargo.toml. `set_paused(paused)` (admin); `charge_compute` checks `!paused`. `version()` returns `"2.0.0"`. Events: `impressions_settled` adds `device` (first 8 bytes hex) and `reports`; event `version` becomes `"2.0.0"`.
- Dev-dependency `p256 = { version = "0.13.2", features = ["ecdsa"] }` (already in Cargo.lock through near-sdk), so tests sign fresh reports at test time and never go stale against the sandbox clock.
- Tests (sandbox): owner registers, pays storage, only once, refund returned; a stranger registering becomes the owner of that pet only; `add_device` owner only, storage paid, 5 at most, 33-byte storage from a 65-byte key; valid report pays (payout gets 80%, budget 20%); same report twice counts 0; older `time_ms` counts 0; unregistered key 0; tampered body 0; another pet's key 0; wrong campaign id 0; `shownMs` 4999 counts 0; locked or covered counts 0; two campaigns with interleaved report times both pay (D2); a fifth campaign evicts a slot and older reports for it count 0; day cap 120 holds; `paused_blocks_money_out` (`settle_signed`, `charge_compute`; `close` and refunds still work); `set_paused` admin only; `version`; 20-report call burns under 150 Tgas (`total_gas_burnt`); `settle_signed` added to `random_operations_keep_the_invariant`. The three unit tests in lib.rs move to the new `register_pet` signature. A real-Mac vector (captured in M3) is checked by a unit test of the signature helper only, since its time will age out.
- Prove: `cd contracts-near && cargo test`. Record the wasm size (`cargo near build non-reproducible-wasm`, then `ls -l target/near/` to **VERIFY** the path) for the cost table.
- Commit: `Vault v2: owner registration, devices, settle_signed with p256_verify, pause, version`.
- **G1 candidate.** Contract code changes after this only for a bug found in M2 or M3.

### M2. Plumbing (5 to 6 h, no NEAR)

Server (`apps/server`):
- `src/chain.ts`: `send(methodName, args, deposit = 0n, gas = 100 Tgas)`; mainnet `rpcUrls` gets `https://archival-rpc.mainnet.fastnear.com` as a second URL (**VERIFY** it accepts `send_tx`); `allowanceLeft()` reads the operator's own access key with `view_access_key` (public key derived from the env key; the private key is never logged).
- `src/state.ts`: `RP_ID` and `RP_SIGNING_KEY` optional; export `WORLD_ON` (both set); still throw if only one is set.
- `src/register.ts` `makeRegister`: takes `worldOn`. Off: no `worldProof`, no nullifier; the owner and payout accounts must exist; `confirmOnChain(pet, owner)` requires `get_pet(name).owner === owner` and returns the owner's `registerTx` from the body. On: unchanged (testnet).
- `src/routes/pets.ts`: delete `PET_STORAGE_DEPOSIT` and the `send("register_pet")` path; `GET /world/sign` answers 404 when World is off; `addImpressions` appends the log entry first and passes its index to `hold()`; `getPet` returns `rpc: rpcUrls[0]` and `views.deviceOnChain` (is the `?device=` key in `get_pet.devices`).
- `src/fraud.ts`: `Held` gets `entries: number[]`; `hold(held, pet, hour, ip, entry)`. `review()` passes them through.
- `src/state.ts` / `src/batch.ts`: payable log entry indices per campaign and pet next to `pending`; `reportsFor(entries, log)` builds `SignedReport`s sorted by time in chunks of 20; marking settled uses the per-report counts the contract returns.
- `src/auth.ts`: `derToRaw(der)` (ASN.1 `30 len 02 lenR R 02 lenS S`, strip leading zeros, left-pad to 32).
- `src/routes/settle.ts` `settle(id)`: per pet, read its payable entries from `logFile(id)`, skip reports whose device is not on chain (with a `settleErrors` reason), send `settle_signed` with gas sized to the batch, apply the returned counts. Keep the per-pet failure isolation and payout pre-check from `36d61d7`. The `verified` pre-check follows D1.
- `src/health.ts` and `src/routes/health.ts`: `HealthInput.allowanceLeft`; 503 under 0.2 NEAR.
- `src/mail.ts` line 47: "verified humans" only when World is on.
- New `scripts/attack-demo.ts` (`--check` read-only; `--live` needs the operator key in env and spends under 0.01 NEAR of gas): transfer, add key, deploy (expect `RequiresFullAccess`), `set_operator` and `register_pet` (expect `MethodNameMismatch`), bad signature, replayed report, over-budget charge (contract refusals). Finish `scripts/prove-keys.ts` (operator key methods subset of the allow-list, purse keys, code hash).
- `package.json`: `attack-demo`.
- Tests: `auth.test.ts` (`derToRaw`: sign DER with Node `crypto`, convert, verify as ieee-p1363; a malformed DER throws); `register.test.ts` (World off: no proof needed, owner mismatch is 409, missing on-chain pet is 409; World on unchanged); `fraud.test.ts` (entries carried through `review`); `batch.test.ts` (reports sorted by time, chunked at 20, marking by returned counts; money logic, so required); `health.test.ts` (allowance under 0.2 NEAR is 503).

Web (`apps/web`):
- `lib/chain.ts`: `registerPet(account, name, payout)` (`call()` with 0.01 NEAR, the vault refunds the rest) and `addDevice(account, pet, keyB64)` (0.005 NEAR); `vaultVersion()` = `view("version")` or null.
- `lib/api.ts`: `RegisterBody.worldProof` optional, `registerTx` added.
- `app/(app)/pet/page.tsx`: when `WORLD_APP_ID` is empty, steps "Details, Register, Move in"; one wallet tx (`registerPet`), then `api.registerPet`; no "One human. One pet." headline, no stamp, no "Prove you're a real person". World path unchanged.
- `app/(app)/pair/page.tsx`: when `vaultVersion()` is `"2.0.0"`, after the NEP-413 pairing send `addDevice` and show the tx; replace "No transaction, no fee".
- `app/(app)/experience/page.tsx`: live-state lines read `NETWORK` and `VAULT_ID`; lines that describe the 15 Nov testnet run stay as history.
- `lib/config.ts`: second mainnet RPC default.

Mac (optional, can wait for main): `Purse+Mac.swift` `rpc` from `backend.info?.rpc`, then `GREMLO_NEAR_RPC`, then testnet; `Models+Mac.swift` `PetInfo.rpc`; `Phone+Mac.swift` `openAccount` opens the purse when `info.purse` exists.

Deploy files: `deploy/vm/gremlo-api-mainnet.service` (`/opt/gremlo-mainnet/apps/server`, `PORT=8788`, `EnvironmentFile=/etc/gremlo/mainnet.env`, `/data/gremlo-mainnet` for store, logs, gallery and `ReadWritePaths`, `HOLDBACK_HOURS=0`, `REQUIRE_SIGNED=1`, `TRUST_PROXY=1`); a second site block in `deploy/vm/Caddyfile` for `mainnet.16-4-100-95.sslip.io` to `127.0.0.1:8788` (**VERIFY** the name resolves). Scripts `scripts/mainnet/10-create-accounts.sh`, `20-deploy-vault.sh`, `25-deploy-factory.sh`, `30-operator-key.sh`, `40-smoke.sh`, `50-lock.sh`, `70-create-purse.sh`, `99-prove.sh`, `60-real-flow.md`, all through `common.sh`, using the Appendix A command forms (checked with `near <subcommand> --help` first), with `gremlo.near` funded with about 14 NEAR (contradiction 16).

Prove: `cd apps/server && npm test && npm run typecheck`; `cd apps/web && npm run typecheck && npm test` (build in `/tmp`); `bash scripts/mainnet/common.sh --selftest`; `NETWORK=mainnet bash scripts/mainnet/10-create-accounts.sh` prints commands and runs none.
Commit: `Mainnet plumbing: owner-signed registration, settle_signed batches, World ID optional, allowance health, mainnet scripts`.

### M3. Testnet rehearsal (3 h, Divesh 2 h, testnet only)

Everything on fresh testnet accounts (D8); nothing touches `vault.gremlo.testnet`, `operator.gremlo.testnet` or the live API.
- `NETWORK=testnet ROOT=gremlo-r1.testnet` for scripts 10, 20, 30, 40, 25, then 50 (lock), then 99.
- Divesh, in his own tabs: the server from the worktree (`cd apps/server && npm start` with a local `.env` for the rehearsal vault, `HOLDBACK_HOURS=0`, World vars unset), the web (`npm run dev`, `NEXT_PUBLIC_NEAR_CONTRACT_ID` = rehearsal vault, World vars unset), the Mac app with `GREMLO_SERVER=http://localhost:8787 GREMLO_WEB=http://localhost:3000 GREMLO_NEAR_RPC=https://test.rpc.fastnear.com`. Register a pet from a testnet wallet, pair, `add_device`, fund a campaign, run Claude Code, wait for `worker: settled`, let the pet think.
- Check: the allowance before and after one call (contradiction 12); `npm run prove:keys` PASS on the rehearsal fixture; `npm run attack-demo -- --live` refuses every step; one real Mac report from the rehearsal log saved as a vector for the M1 unit test; create one purse through the factory and pay one thought from it.
- Evidence under `docs/rehearsal/` (command output, tx hashes, no keys).
- Commit: `Testnet rehearsal of the mainnet scripts, with evidence`.
- **G1 confirmed** only if the lock step worked and the real Mac report settled. If 2B is not green by Sun 29 Nov 2 PM IST, build with `legacy-settle`, ship 2B-lite (2 h) and say so in the docs.

### M4. Priority Milestone 1: mainnet + one real flow (5 to 6 h, all Divesh, real NEAR)

Starts after BotFolio ships (29 Nov, 9 PM IST); target 30 Nov.
1. **G2.** Divesh reads the dry-run output of scripts 10 and 20, the cost table (section 7) and the recorded wasm sha256 and code hash. Wait for "go".
2. Script 10, then 20 (deploy and init in one tx), then the read-only checks `get_admin`, `get_operator`, `get_totals`, `near contract inspect` (no `settle_impressions`).
3. Script 30: the operator function-call key (methods per D1, allowance 2 NEAR). Divesh pastes the printed private key into `/etc/gremlo/mainnet.env` with `sudoedit` on EC2. Nobody else sees it.
4. Push `mainnet-upgrade` (stop-and-ask), then on EC2: clone to `/opt/gremlo-mainnet` at that commit, install the unit and Caddy block, start `gremlo-api-mainnet`; `curl -s https://mainnet.16-4-100-95.sslip.io/health` is 200. Second Vercel project on `mainnet-upgrade` with mainnet env and no World vars.
5. Script 40 smoke with tiny values (`brand.gremlo.near` campaign 0.2 NEAR at 0.003 per view, 1 h window; owner registers the pet and adds the Mac; one signed view; one charge). Fix anything here, while the admin can still redeploy.
6. Script 25: factory on `pets.gremlo.near`.
7. **G3.** Claude pastes `get_admin`, `get_operator`, `get_totals`, both key lists and the code hash; Divesh types `LOCK`; script 50 deletes every key on `vault.gremlo.near` and `pets.gremlo.near`; `list-keys` prints no rows.
8. Real flow on the locked vault: Divesh's Mac with `GREMLO_SERVER=https://mainnet.16-4-100-95.sslip.io GREMLO_WEB=<mainnet web> GREMLO_NEAR_RPC=https://rpc.mainnet.fastnear.com` (`launchctl setenv`, reopen); a Claude Code run; `journalctl -u gremlo-api-mainnet -f` shows `worker: settled campaign 1`; the pet thinks; `compute_charged` carries a `chatcmpl-` id; `cd apps/server && npm run verify <id>` prints SIGNED (Divesh supplies `NEAR_AI_API_KEY` in his own shell).
9. Script 70: the owner creates the purse (2 NEAR); `PURSE_PARENT=pets.gremlo.near` in `mainnet.env`, restart; one more thought paid by `pay_inference` from the Mac's key.
10. `npm run prove:keys` and `npm run attack-demo -- --live` (run on EC2 as root, under 0.01 NEAR of gas) against mainnet.
- Prove: the spec's item 1, 2A and 3 verification commands; `npm run verify:public` with the testnet fixture still exits 0 (submission untouched).
- Commit: `Mainnet run: accounts, vault v2, factory, lock, one real flow` (fixture and PROOF.md rows, no secrets).

### M5. Truth and proof (5 to 6 h, Divesh 1 h review, no NEAR)

- `apps/server/scripts/verify-public.ts`: `--fixture <path>`, `fx.rpcLive` instead of the two hard-coded URLs, plus checks for the key policy (shared code with `prove-keys.ts`), the `get_totals` invariant, the completion id in the flow tx's `compute_charged` log, and `/stats` against the chain. New `apps/server/fixtures/public-proof.mainnet.json` (adds `policy`, `commit`, `rpcLive`); `rpcLive` added to `public-proof.json`. `package.json`: `verify:public:mainnet`. `.github/workflows/ci.yml` job `proof`: run both fixtures.
- Docs: README (badge 31, Judging block 38-45, Proof 122-145 with a Mainnet run table above the testnet one, What's real 147-168 with rows for No god key, Views verified on chain if 2B shipped, World ID "built, used with the simulator on testnet, off on mainnet", purse deployed, repo map 218, test counts 191-196, code-hash wording at 43 and 151); JUDGE.md (19-24, 32-38, a three-command mainnet path); SECURITY.md (keys table 7-14, sections 16-30 rewritten, immutable vault); new `docs/TRUST.md` (Appendix C plus the gaps in section 3); `docs/ATTACK-DEMO.md` (from `--live` output); `docs/DEPLOY.md` (line 5, the EC2 reality, a Mainnet instance section, locked vault); `HANDOFF.md` (mainnet accounts and env names); `PROOF.md` (mainnet section with list-keys output); `CHANGELOG.md`; `contracts-accounts/README.md` (mainnet, `pets.gremlo.near`); `docs/WORLD_DEBRIEF.md` (label the 0G link as the earlier build).
- Copy that claims a human check (contradiction 22): network-aware or removed on the mainnet web.
- Demo capture list per spec item 5; recording by Dijo or Gokul.
- Prove: from a fresh clone, `cd apps/server && npm ci && npm run verify:public && npm run verify:public:mainnet && npm run prove:keys`, exit 0 with no `.env`; every test suite green; CI green on the branch.
- **G4.** Divesh reads the README diff; the X post only as a draft card he approves.
- Commit: `Mainnet docs and proof: verify-public for both networks, TRUST, ATTACK-DEMO`.

### M6. Optional (3 to 8 h)

Item 6a (Intents dry-run quote), item 7 (TDX nonce and report-data checks in `verifyCompletion`), the `/prove` page. Only after M5.

## 6. Gates

| Gate | When | Condition | Who |
|---|---|---|---|
| G1 | candidate after M1, confirmed after M3 | sandbox tests green; a real Mac report settled on the rehearsal vault; the rehearsal lock worked. Latest Sun 29 Nov 2 PM IST, else 2B-lite | Claude reports, Divesh accepts |
| G2 | before the first mainnet signature | dry-run output of scripts 10 and 20, cost table, wasm hash | Divesh says "go" |
| G3 | before the lock | `get_admin`, `get_operator`, `get_totals`, key lists, code hash pasted | Divesh types `LOCK` |
| G4 | before publishing | README diff read; X draft card approved word for word | Divesh |

## 7. Stop-and-ask list (real NEAR or outside systems)

| Step | What | NEAR (about) |
|---|---|---|
| M4.2 script 10 | create `gremlo.near` (about 14, it funds the rest), `vault` 4, `operator` 2, `pets` 4, `brand` 1 | 14 out of Divesh's wallet, mostly stake and balances |
| M4.2 script 20 | deploy and init the vault | gas; storage stake from the vault's balance (wasm size from M1) |
| M4.3 script 30 | add the operator function-call key; key into `mainnet.env` | gas; the 2 NEAR allowance is a cap, not a payment |
| M4.4 | push the branch; EC2 checkout, unit, Caddy; Vercel project | 0 |
| M4.5 script 40 | campaign 0.2, `register_pet` 0.01, `add_device` 0.005, one settle, one charge | about 0.22 |
| M4.6 script 25 | deploy and init the factory | gas; stake about 2.6 from `pets` |
| M4.7 script 50 | delete every key on `vault` and `pets` (irreversible) | gas |
| M4.9 script 70 | owner creates the purse | 2 from the owner |
| M4.10 | `attack-demo --live` on mainnet | under 0.01 |
| M5 / G4 | push, X post | 0 |

Peak about 16 NEAR (about 49 USD at 3.05; recheck the price on the day). True burn under 0.3 NEAR.

## 8. Estimates, baseline and actuals

| Milestone | Estimate | Divesh at the keyboard | Real NEAR |
|---|---|---|---|
| M0 | 1 h | 15 min | no |
| M1 | 6-7 h | review the test list (or Dijo/Gokul) | no |
| M2 | 5-6 h | none | no |
| M3 | 3 h | about 2 h | testnet only |
| M4 | 5-6 h | all of it | yes |
| M5 | 5-6 h | about 1 h | no |
| Core total | 25-29 h | about 8-9 h | |

Against the spec's 23-27 h: plus 1 h in M1 (D2, the day ring, the sandbox spike), plus 1.5 h in M2 (World ID optional in server and `/pet`), minus 1.5 h (no sandbox e2e, D7), plus the M3 allowance check.

Minimum if time runs out (spec section 7): M0, 2A with 2B-lite, the M4 flow on mainnet, README with World ID labelled off. Skip 2B, item 3 (state "built, not deployed"), M6.

Parallel work without keys: M1 touches only `contracts-near`, so it can run now next to Phase 1. `prove-keys.ts`, `verify-public.ts --fixture` and the M5 docs skeleton can run beside M1 in their own worktrees.

Test baseline (filled in M0): _pending._

Actual time spent and anything cut (filled as we go): _pending._
