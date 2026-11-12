# Proof (draft for the README)

Every value here comes from a real run on NEAR testnet or NEAR AI Cloud. Blank rows are filled from the demo run; nothing is estimated or made up. Explorer: https://testnet.nearblocks.io

## Contract

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

## The loop (fill from the demo run)

| Step | Tx or id | Link |
|---|---|---|
| Pet registered (`register_pet`) | | |
| Pet verified after World ID (`set_verified`) | | |
| Compute budget before: `compute_budget {"pet_id":"mochi"}` | | |
| Brand funds a campaign (`create_campaign`) | | |
| Impressions settled (`impressions_settled`: paid + compute) | | |
| Compute budget after settlement | | |
| Smart-model call: NEAR AI completion id | | `npm run verify <id>` |
| Charge for that call (`charge_compute`, log carries the completion id) | | |
| `npm run verify` on that completion | | |
| Optional: cheap-model call and its charge | | |
| Optional: campaign closed and refunded (`close`) | | |

## Wording rules for the README

- "The pet reimburses its AI usage onchain. Each NEAR AI call is charged against the pet's compute budget, with the TEE-signed completion id in the log. The operator holds the NEAR AI credits; the pet can't buy credits directly yet."
- "Each AI call is charged a fixed per-tier rate in NEAR, not the real USD bill from NEAR AI."
- Never call the loop self-funded beyond that.
