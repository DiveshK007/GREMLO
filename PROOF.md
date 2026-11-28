# Proof (draft for the README)

Every value here comes from a real run on NEAR testnet or NEAR AI Cloud. Blank rows are filled from the demo run; nothing is estimated or made up. Explorer: https://testnet.nearblocks.io

## Mainnet run (28 Nov 2026)

Accounts: admin `divzzz007.near`, vault `vault.divzzz007.near` (code hash `5pu1xBnBucsruBkTV4jg5j9WBMk2w95nNySpz9E58RSZ`, wasm sha256 `47b3dc61deceda91aa1620047f5832000a3a1f9dfd56f9f827fe2d541e279f22`), operator `operator.divzzz007.near`.

- create vault account `CypRsqok4sXycjHokKjncusvbFQMAHbeazmMGySb9CCW`, operator account `H6u7tDVASkxaGyMKhvpdh635YLFmYKmft3YrJnCxmNFB`
- deploy + init `GNXUhMtkQaqCAk6gspC6xiGZaUHywn7WcFTcjnvUDvtP`
- register `mochi` `FFRc8bahstnTHpBHo3ATBZMN4W9wuGG3TU8oMuDt4REH`, set_verified `FVvqeJwLSnpSF6GNnmB8T3qkTvvwphKYbiyVXdz4WqTY`
- campaign #1 (0.02 NEAR) `GHV83PKm31hQsi7LRVvw3AXyDvbu4JcrY3zQBt4KeLEv`
- settle 1 view `8deWGCfcZkw6X6iAMwkbJGZSBpDkKffNEBbkrke8v3VJ` (event impressions_settled: paid 0.0024, compute 0.0006)
- charge_compute 0.0005 NEAR `BiQ5xUEWLR3i9TS3pquvqzaSkT6RYwLZp2ky4pzt8yjk`, completion `chatcmpl-30c8f76f-e514-44ab-96d8-3295700a9523`
- `npm run verify chatcmpl-30c8f76f-e514-44ab-96d8-3295700a9523`: SIGNED, signer 0xfe0071895500a9755c18044948ab4f4e1a7f337e (deepseek-ai/DeepSeek-V4.1-Flash-1017), verified against NEAR's attestation report
- second view settled `8BzX62XxcWEJzSXmgFkh2hY6uPt9Cv8RkagXyFQib2h1`
- get_totals after: deposited 0.01812, paid to pets 0.0048, compute budgets 0.0007, charged 0.0005, remaining 0.01212 (they add up)

Not locked (full-access key on the vault), operator-settled, World ID off, funded by the owner: see the README.

## Final run accounts (gremlo.testnet)

The final run uses new accounts; the deploy, init and loop rows are filled from that run.

| Account | Role | Creation tx |
|---|---|---|
| `gremlo.testnet` | admin (10 NEAR from the faucet) | [`FfLHrk39dTWCQqW7PpcwHWqDauPghMgs4ot37nw4tvTA`](https://testnet.nearblocks.io/txns/FfLHrk39dTWCQqW7PpcwHWqDauPghMgs4ot37nw4tvTA) |
| `vault.gremlo.testnet` | vault contract (3 NEAR) | [`evTcxm7JALCQ9bJTYAvodkyuEC8mRwiixxsURwbSxsC`](https://testnet.nearblocks.io/txns/evTcxm7JALCQ9bJTYAvodkyuEC8mRwiixxsURwbSxsC) |
| `operator.gremlo.testnet` | operator (1 NEAR) | [`7iB2EnwdXSpMKf6XqaBygpJHEpAGjMpupSkr3Q3aJeqx`](https://testnet.nearblocks.io/txns/7iB2EnwdXSpMKf6XqaBygpJHEpAGjMpupSkr3Q3aJeqx) |
| `owner.gremlo.testnet` | pet owner (1 NEAR) | [`E9jsBNdoRV9zxxhzDFiTdeE5nVHjwWmJhrN1exmzt4tJ`](https://testnet.nearblocks.io/txns/E9jsBNdoRV9zxxhzDFiTdeE5nVHjwWmJhrN1exmzt4tJ) |
| `byte.gremlo.testnet` | pet payout (0.1 NEAR) | [`GYT2icscofQBXC1TkKVAVqCk1fEX5AWcy6ym7s8woFrq`](https://testnet.nearblocks.io/txns/GYT2icscofQBXC1TkKVAVqCk1fEX5AWcy6ym7s8woFrq) |
| Vault deployed and initialised (`DeployContract` + `new`, admin `gremlo.testnet`, operator `operator.gremlo.testnet`) | [`12bj3uDkB6ufrMmKS7m4s85xma9CC1zhgevS7eMbJ4bq`](https://testnet.nearblocks.io/txns/12bj3uDkB6ufrMmKS7m4s85xma9CC1zhgevS7eMbJ4bq) | |
| Operator (`get_operator`) | `operator.gremlo.testnet` | |
| Code hash (sha256, base58) | `AeXXhh355asstWmnF9XzLHowUBoTXtAao7VR4WhF7gdb` (matches a local `cargo near build non-reproducible-wasm` of `contracts-near`) | |

## The loop: FINAL RUN (15 Nov 2026)

On `vault.gremlo.testnet`, 03:09 to 03:50 IST. Every hash below was checked on testnet RPC on 2026-11-15: each tx ended in `SuccessValue` with no failed receipt, and the events are the vault's own logs.

Pet `mochi`: owner `owner.gremlo.testnet`, payout `owner.gremlo.testnet` (the payout field was left at its default, the owner; `byte.gremlo.testnet` wasn't used). Brand `notchi.testnet`, campaign 1.

| # | Step | Tx | What the chain shows |
|---|---|---|---|
| 1 | Pet registered (`register_pet`, by the operator after the World ID check) | [`5xuUysyigMP4bARt3WdRHTW9byCyKiifiwi4oPd8fWho`](https://testnet.nearblocks.io/txns/5xuUysyigMP4bARt3WdRHTW9byCyKiifiwi4oPd8fWho) | `pet_registered` mochi, owner and payout `owner.gremlo.testnet` |
| 2 | Pet verified (`set_verified`) | [`6EAhsDt7Ae6mqq1ipxBgP22Yra9ccWB1fSJ9sdsdzu9X`](https://testnet.nearblocks.io/txns/6EAhsDt7Ae6mqq1ipxBgP22Yra9ccWB1fSJ9sdsdzu9X) | `pet_verified` |
| 3 | Brand funds campaign 1 (`create_campaign`, 0.1 NEAR attached, by `notchi.testnet`) | [`214EyrLM5Jwqsn2R2gDbGrnBYXsKQsLnZXvCXXTougn7`](https://testnet.nearblocks.io/txns/214EyrLM5Jwqsn2R2gDbGrnBYXsKQsLnZXvCXXTougn7) | `campaign_created` id 1, budget 0.09812 NEAR, 0.003 NEAR per view |
| — | Compute budget before the first settlement | | 0 |
| 4 | View 1 settled (`settle_impressions`) | [`FFdmieVQ26YyJcHwkvcSnSveA4EfG6SxYUE2JwWBQUQB`](https://testnet.nearblocks.io/txns/FFdmieVQ26YyJcHwkvcSnSveA4EfG6SxYUE2JwWBQUQB) | `impressions_settled`: 0.0024 NEAR paid to `owner.gremlo.testnet`, 0.0006 NEAR into the compute budget |
| 5 | Smart-model call charged (`charge_compute`) | [`E1vh3VKeVobQJPZjC5PKcpmiTfWzoqkGurW4KhCSMH1d`](https://testnet.nearblocks.io/txns/E1vh3VKeVobQJPZjC5PKcpmiTfWzoqkGurW4KhCSMH1d) | `compute_charged` 0.0005 NEAR, completion `chatcmpl-cc26d4e5-abf1-4837-b10f-7543f37ce156`, budget left 0.0001 |
| 6 | Cheap-model call charged (`charge_compute`) | [`GHMAHr4ad8hZKJf7jR9Mgz92K1wXKBh4srFTbanCrBzq`](https://testnet.nearblocks.io/txns/GHMAHr4ad8hZKJf7jR9Mgz92K1wXKBh4srFTbanCrBzq) | `compute_charged` 0.0001 NEAR, completion `cccbcb67e3e74cc9af1788f20c910d62`, budget left 0 |
| 7 | Brand tops up campaign 1 (`top_up`, by `notchi.testnet`) | [`Akz9UDRZqkSM5AjjEubTZhfv6QD7U52kjsPQ63R4tNcr`](https://testnet.nearblocks.io/txns/Akz9UDRZqkSM5AjjEubTZhfv6QD7U52kjsPQ63R4tNcr) | `campaign_topped_up` +0.5 NEAR, campaign budget 0.59812 NEAR. The campaign's budget, not the pet's compute budget |
| 8 | View 2 settled (`settle_impressions`) | [`CNvNmMvBLdgdXzCUFr852CRdjRCrWb43sVLjSuoUa95M`](https://testnet.nearblocks.io/txns/CNvNmMvBLdgdXzCUFr852CRdjRCrWb43sVLjSuoUa95M) | `impressions_settled`: 0.0024 NEAR paid, 0.0006 NEAR into the compute budget |
| 9 | Smart-model call charged (`charge_compute`) | [`8gDVVjKkHYh7VkGWpwvJ5hS7AdpYUUAAWMRVZuWj1V9Z`](https://testnet.nearblocks.io/txns/8gDVVjKkHYh7VkGWpwvJ5hS7AdpYUUAAWMRVZuWj1V9Z) | `compute_charged` 0.0005 NEAR, completion `chatcmpl-5132d660-f00d-4cea-9ee6-832310f23900`, budget left 0.0001 |
| 10 | Cheap-model call charged (`charge_compute`) | [`J6a5MxUP1EV5591XNVRV8i4B194hAuGnv8wW8eggU5cg`](https://testnet.nearblocks.io/txns/J6a5MxUP1EV5591XNVRV8i4B194hAuGnv8wW8eggU5cg) | `compute_charged` 0.0001 NEAR, completion `49b3f9cae70d48f8bca2aca2d7d97ae7`, budget left 0 |

The budget moved exactly as the vault's rules say: 0 → +0.0006 (view 1) → −0.0005 smart → −0.0001 cheap → 0 → +0.0006 (view 2) → −0.0005 smart → −0.0001 cheap → 0. Every thought was paid from views; nothing was added to the pet's compute budget by hand.

Vault state read after the run (`get_pet mochi`, `get_campaign 1`, `get_totals`):

| What | Value |
|---|---|
| Pet `mochi` | verified, 2 views, earned 0.0048 NEAR, compute share 20%, compute budget 0, compute spent 0.0012 NEAR, daily cap 0.02 NEAR |
| Campaign 1 | brand `notchi.testnet`, budget 0.59812 NEAR, spent 0.006 NEAR, open |
| Totals | deposited 0.59812 NEAR, paid to pets 0.0048, compute charged 0.0012, remaining 0.59212, refunded 0 |

Notes on the final run:
- Pairing the Mac to the pet is a signed message (NEP-413) checked by the server, not a transaction, so it has no hash on chain. The vault's history has no other calls than the ones above.
- `npm run verify chatcmpl-cc26d4e5-abf1-4837-b10f-7543f37ce156` (smart #1), 2026-11-15 04:09 IST: SIGNED. The signature recovers to `0xfe0071895500a9755c18044948ab4f4e1a7f337e`, an attested key of the NEAR TEE serving `deepseek-ai/DeepSeek-V4.1-Flash-1017`, the same key as in the dry run. The first try said NOT VERIFIED: the attestation report now lists that key twice for the model ("2 matches"), and the verifier wanted exactly one. It now accepts the signer if it is any attested key for that model, and still checks the nonce (`apps/server/src/verify.ts`, tested). The other three completion ids were not run through it.

## Contract: DRY RUN (old accounts, before the rename)

The dry run ran on the original testnet accounts, which keep their `notchi` names.

| What | Value | Link |
|---|---|---|
| Vault contract | `vault.notchi.testnet` | https://testnet.nearblocks.io/address/vault.notchi.testnet |
| Vault account created (`CreateAccount`, `Transfer`, `AddKey`, signed by `notchi.testnet`) | `3K1Jx6WqYWrowJvDritzhuA5JqcVFgPR8LUcJtahqQ2N` | https://testnet.nearblocks.io/txns/3K1Jx6WqYWrowJvDritzhuA5JqcVFgPR8LUcJtahqQ2N |
| Deployed and initialised (`DeployContract` + `new`) | `8UBPuVJqWp5UG7HHzf4myAmQfBr8R8Lfap67bMo2KEB3` | https://testnet.nearblocks.io/txns/8UBPuVJqWp5UG7HHzf4myAmQfBr8R8Lfap67bMo2KEB3 |
| Admin (`get_admin`) | `notchi.testnet` | |
| Operator (`get_operator`) | `operator.notchi.testnet` | |
| Source | `contracts-near/src/lib.rs`, built with `cargo near build non-reproducible-wasm` | |

Accounts: `notchi`, `vault`, `operator`, `brand` and `mochi` (all `.notchi.testnet`), funded from the testnet faucet.

## NEAR AI Cloud (private inference in a TEE)

| What | Value | How to check |
|---|---|---|
| Completion from `npm run ping` (`packages/brain`) | `5d04dab890964a6e8bb208db3d274202` | `cd apps/server && npm run verify 5d04dab890964a6e8bb208db3d274202` |
| Result | SIGNED. The signature recovers to the attested key of the NEAR TEE serving `Qwen/Qwen3.8-27B` | https://cloud.near.ai/verify |

`npm run verify` checks the signature, the signer against NEAR's attestation report and a fresh nonce. It does not check the hardware quotes or the request/response hashes; cloud.near.ai/verify does.

## The loop: DRY RUN (12 Nov 2026)

> **This is the dry run.** It passed end to end on testnet, but it ran before the redesign and rename.
> The README's proof will come from a clean re-run after those; this section stays as the record of the first pass.
> Every hash below was checked on testnet RPC (archival) for status and events on 2026-11-12.

Pet `mochi`: owner `brand.notchi.testnet` (the account connected at registration), payout `mochi.notchi.testnet`.

| # | Step | Tx | What the chain shows |
|---|---|---|---|
| 1 | Pet registered (`register_pet`, by the operator after the World ID check) | [`CuW3LzUWzA4PyZTuzuM2qKjoZHnhXhi67d7G8UC2d4gW`](https://testnet.nearblocks.io/txns/CuW3LzUWzA4PyZTuzuM2qKjoZHnhXhi67d7G8UC2d4gW) | `pet_registered` |
| 2 | Pet verified (`set_verified`) | [`5mAun8ojQNQu4Rs6RRk5GG7sa89vi1ZRLgZii8dBjzeU`](https://testnet.nearblocks.io/txns/5mAun8ojQNQu4Rs6RRk5GG7sa89vi1ZRLgZii8dBjzeU) | `pet_verified` |
| 3 | Payout moved to the pet's own account (`set_payout`, signed by the owner) | [`6TeYqRWrHfn5WQ9SHF4LKjYEtR2omaRcAg8p873kf7EW`](https://testnet.nearblocks.io/txns/6TeYqRWrHfn5WQ9SHF4LKjYEtR2omaRcAg8p873kf7EW) | `payout_changed` → `mochi.notchi.testnet` |
| 4 | Campaign #1 (2 h, zero views; see note) closed and refunded by the worker (`close`) | [`HJZvga8o2dAPdKk5P6uSrq42C16tG6uQUQeb9sBiPrvq`](https://testnet.nearblocks.io/txns/HJZvga8o2dAPdKk5P6uSrq42C16tG6uQUQeb9sBiPrvq) | `campaign_closed`, refund 0.09812 NEAR |
| 5 | Brand funds campaign #2 (`create_campaign`, by `notchi.testnet`) | [`84GBhoKvWvYtjy1DR2rYTXPrvZ7JafqBVhjMFcjDCBbw`](https://testnet.nearblocks.io/txns/84GBhoKvWvYtjy1DR2rYTXPrvZ7JafqBVhjMFcjDCBbw) | `campaign_created` id 2, budget 0.09812 NEAR, 0.003 NEAR per view |
| — | Compute budget before the first settlement | | 0 (pet sleeping: compute budget empty) |
| 6 | View 1 settled (`settle_impressions`) | [`GfjjM3xzdNS3XvdqHiwChJ3BhU2MrXaaMCcoGDMW5WAy`](https://testnet.nearblocks.io/txns/GfjjM3xzdNS3XvdqHiwChJ3BhU2MrXaaMCcoGDMW5WAy) | `impressions_settled`: 0.0024 NEAR paid to `mochi.notchi.testnet`, 0.0006 NEAR into the compute budget |
| 7 | Smart-model call charged (`charge_compute`, DeepSeek V4.1 Flash) | [`2pvnEWYwKC4G5RNWvaPaTjmB6RDwFN49GkpEQdLTVjGm`](https://testnet.nearblocks.io/txns/2pvnEWYwKC4G5RNWvaPaTjmB6RDwFN49GkpEQdLTVjGm) | `compute_charged` 0.0005 NEAR, completion `chatcmpl-08f9bae5-8763-4a05-844a-c4e27a81728e`, budget left 0.0001 |
| 8 | Cheap-model call charged (`charge_compute`, Qwen 3.8 27B) | [`BZH3mcLpvGUiuyYAaK6xW2sqPix1skkGWfWauC33TePo`](https://testnet.nearblocks.io/txns/BZH3mcLpvGUiuyYAaK6xW2sqPix1skkGWfWauC33TePo) | `compute_charged` 0.0001 NEAR, completion `d46e39b976894fa6847d97b32d847cec`, budget left 0 |
| 9 | View 2 settled (`settle_impressions`) | [`C34DZaj2eV3YQKcutNVqGffmuLnZ9YAqu9wmWffakbKY`](https://testnet.nearblocks.io/txns/C34DZaj2eV3YQKcutNVqGffmuLnZ9YAqu9wmWffakbKY) | `impressions_settled`: 0.0024 NEAR paid, 0.0006 NEAR into the compute budget |
| 10 | Smart-model call charged (`charge_compute`, DeepSeek V4.1 Flash) | [`Erz9f3Pdy8CHVQE8SryNz1vhnewSP36QdGc8sGfaVsW7`](https://testnet.nearblocks.io/txns/Erz9f3Pdy8CHVQE8SryNz1vhnewSP36QdGc8sGfaVsW7) | `compute_charged` 0.0005 NEAR, completion `chatcmpl-2cbe75aa-db0b-4fa6-91f6-5c731b0560c1`, budget left 0.0001 |
| 11 | `npm run verify chatcmpl-2cbe75aa-db0b-4fa6-91f6-5c731b0560c1` | | SIGNED by the attested NEAR TEE serving `deepseek-ai/DeepSeek-V4.1-Flash-1017`, signer `0xfe0071895500a9755c18044948ab4f4e1a7f337e` |
| — | Compute budget after | | 0.0001 NEAR |

The budget moved exactly as the vault's rules say: 0 → +0.0006 (view 1) → −0.0005 smart → −0.0001 cheap → 0 → +0.0006 (view 2) → −0.0005 smart → 0.0001.
The smart signer `0xfe00…337e` is the same key the attestation report listed for DeepSeek V4.1 Flash during the verifier's development.

Notes on the dry run:
- Campaign #1 got no views. The Mac app kept an `asleep` pet home even while the agent worked, so the sign never showed (the RPC was rate-limited, so the server reported the pet asleep). Fixed in `1a01dc9`; campaigns now default to 24 h (`a6902fb`).
- The smart #1 hash was first written down with two letters swapped (`…RNVwa…`). The hash above is the one the server recorded, and it is the one on chain.
- Only the smart #2 completion was run through `npm run verify` in this dry run.

## Wording rules for the README

- "The pet reimburses its AI usage onchain. Each NEAR AI call is charged against the pet's compute budget, with the TEE-signed completion id in the log. The operator holds the NEAR AI credits; the pet can't buy credits directly yet."
- "Each AI call is charged a fixed per-tier rate in NEAR, not the real USD bill from NEAR AI."
- Never call the loop self-funded beyond that.
