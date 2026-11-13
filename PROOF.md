# Proof (draft for the README)

Every value here comes from a real run on NEAR testnet or NEAR AI Cloud. Blank rows are filled from the demo run; nothing is estimated or made up. Explorer: https://testnet.nearblocks.io

## Final run accounts (gremlo.testnet)

The final run uses new accounts; the deploy, init and loop rows are filled from that run.

| Account | Role | Creation tx |
|---|---|---|
| `gremlo.testnet` | admin (10 NEAR from the faucet) | [`FfLHrk39dTWCQqW7PpcwHWqDauPghMgs4ot37nw4tvTA`](https://testnet.nearblocks.io/txns/FfLHrk39dTWCQqW7PpcwHWqDauPghMgs4ot37nw4tvTA) |
| `vault.gremlo.testnet` | vault contract (3 NEAR) | [`evTcxm7JALCQ9bJTYAvodkyuEC8mRwiixxsURwbSxsC`](https://testnet.nearblocks.io/txns/evTcxm7JALCQ9bJTYAvodkyuEC8mRwiixxsURwbSxsC) |
| `operator.gremlo.testnet` | operator (1 NEAR) | [`7iB2EnwdXSpMKf6XqaBygpJHEpAGjMpupSkr3Q3aJeqx`](https://testnet.nearblocks.io/txns/7iB2EnwdXSpMKf6XqaBygpJHEpAGjMpupSkr3Q3aJeqx) |
| `owner.gremlo.testnet` | pet owner (1 NEAR) | [`E9jsBNdoRV9zxxhzDFiTdeE5nVHjwWmJhrN1exmzt4tJ`](https://testnet.nearblocks.io/txns/E9jsBNdoRV9zxxhzDFiTdeE5nVHjwWmJhrN1exmzt4tJ) |
| `byte.gremlo.testnet` | pet payout (0.1 NEAR) | [`GYT2icscofQBXC1TkKVAVqCk1fEX5AWcy6ym7s8woFrq`](https://testnet.nearblocks.io/txns/GYT2icscofQBXC1TkKVAVqCk1fEX5AWcy6ym7s8woFrq) |
| Vault deployed and initialised | | |

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
