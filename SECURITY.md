# Security

Gremlo runs on NEAR testnet today. Nothing here protects real money yet, and this page says what each key can do so you can judge the design before mainnet.

## Keys

| Key | Held by | What it can do |
|---|---|---|
| **Operator key** | The API server, in its environment (never in the repo) | Calls `register_pet`, `set_verified`, `settle_impressions` and `charge_compute` on the vault, as `operator.gremlo.testnet`. |
| **Admin key** | The deployer (`gremlo.testnet`) | Calls `set_operator` to rotate the operator. |
| **Vault full-access key** | The deployer, on `vault.gremlo.testnet` | Everything, including replacing the contract code. |
| **Device key** | One per Mac install, in the Secure Enclave (P-256, not exportable) | Signs the view reports and the requests that earn or spend money. The server checks every signature. |
| **Owner wallet** | The pet's owner | Signs a NEP-413 message to pair a device to the pet. Changing the payout account is a transaction signed by the owner. |
| **Hook secret** | One per Mac install, in `~/.gremlo/` with mode 0600 | Lets only local Claude Code hooks reach the app's local hook server. |

### What a stolen operator key could do

The operator registers and verifies pets, so a stolen key could register a pet with the thief's payout account, verify it, and settle views until open campaigns run out of budget. It cannot take the vault's balance in any other way, cannot touch the admin or full-access key, and `charge_compute` is held by each pet's daily cap and compute budget. The admin can rotate the operator with `set_operator`, which stops the thief but does not return what was paid out. Every payout is a public transaction, so it would show up on chain.

Limits that exist now: each view needs a Secure Enclave signature the server checks, the server rate-limits settlement, and the contract refuses to settle beyond a campaign's budget or after its end plus the grace period. The server holds the operator key, so a server compromise is an operator compromise.

### The full-access key

`vault.gremlo.testnet` still has a full-access key held by the deployer. With it the code could be replaced and the balance moved, so for now the contract's rules are only as strong as that key's owner. This is acceptable on testnet and is not acceptable on mainnet. Before mainnet the plan is:

1. Deploy the final, audited contract.
2. Delete every full-access key on the vault account, so the code cannot change and nobody can move the balance except through the contract's own methods.
3. Decide the upgrade path before step 2, because afterwards there is none. If upgrades are needed, put the key behind a multisig first instead.

Until that is done, treat the contract as upgradable by one person.

## Reporting an issue

Please do not open a public issue for something exploitable. Use GitHub's private report instead: the **Security** tab of [DiveshK007/GREMLO](https://github.com/DiveshK007/GREMLO/security), then **Report a vulnerability**. Include what you found, how to reproduce it, and what it affects.

For anything that is not exploitable (a wrong claim in the docs, a hardening idea), a normal issue is fine.

This is a solo project. I will answer reports as fast as I can and will say plainly what is fixed, what is not, and what is deployed.
