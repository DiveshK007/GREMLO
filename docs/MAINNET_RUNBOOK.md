# Mainnet runbook (fast path)

Decided 28 Nov 2026: ship mainnet now with the vault that runs on testnet today (v1, built and tested), **not
locked**, and one real flow: a view settles on mainnet and pays for one TEE-signed NEAR AI call. Contract v2 (no god
key, on-chain Secure Enclave check) comes later, as a new vault account; `docs/MAINNET_PLAN.md` has it.

What this means, said plainly in the README once it runs:
- The mainnet vault keeps its full-access key for now (admin `gremlo.near` can redeploy it). Not "no god key" yet.
- Views are settled by the operator, as on testnet.
- World ID is off. Registration is invite-only (`REGISTER_OWNERS`): the owner signs a message with their wallet.
  `verified` onchain means "registered by an invited owner", not "a human was checked".

## Cost

About 8 NEAR (~$25). Most of it stays in your accounts:

| What | NEAR |
|---|---|
| `gremlo.near`, which funds the two below | 4 |
| `vault.gremlo.near`, of which ~1.9 is contract storage (189,267-byte wasm) | 2.4 |
| `operator.gremlo.near`: gas, 0.01 per pet registered (mostly refunded) | 1 |
| First campaign, from your wallet. The unspent part is refunded after it ends | 0.2 |
| Gas for everything, on top | < 0.1 |

## Rehearsed on testnet, 28 Nov

The same scripts ran against throwaway testnet accounts, with the new World-ID-off server running locally:
- Accounts were created.
- The vault was deployed and initialised in one tx.
- A campaign was created.
- An invited owner registered a pet with a wallet signature. A second pet for the same owner, and an owner not on the list, were both refused.
- A device was paired.
- A signed view was accepted, and an unsigned one refused.
- The worker settled the view on chain: the pet got 0.0024 NEAR and its compute budget 0.0006 NEAR.
- Not rehearsed: the AI call and its charge. They work on the testnet API today, and mainnet uses the same NEAR AI key.

## Steps

Each script prints what it will send and what it costs, and sends only with `CONFIRM_MAINNET=yes`. Run them from
the repo root. `YOU` is your funded wallet account, for example `yourname.near`.

0. **You:** put about 10 NEAR in a mainnet wallet. Then put its key in the macOS keychain for the `near` CLI, in your
   own Terminal: `near account import-account using-seed-phrase` (it asks for the phrase there, not in chat). Choose
   network `mainnet` and storage `keychain`.
1. **EC2 (no NEAR):** `OWNER=YOU REV=<commit> bash scripts/mainnet/10-ec2-prepare.sh`. This makes a pinned checkout
   in `/opt/gremlo-mainnet` and `/data/gremlo-mainnet`. It generates the operator key on the box, in root-only
   `/etc/gremlo/mainnet.env`, and copies the NEAR AI lines from the testnet env without showing them. It prints only
   the operator's public key.
2. **Accounts (7.4 NEAR):** `FUNDER=YOU OPERATOR_PUBLIC_KEY=ed25519:… bash scripts/mainnet/20-accounts.sh`, then the
   same command with `CONFIRM_MAINNET=yes`.
3. **Vault (gas):** `bash scripts/mainnet/30-deploy-vault.sh`, then again with `CONFIRM_MAINNET=yes`. It refuses a wasm
   whose sha256 isn't `47b3dc61…f22`.
4. **API (no NEAR):** `bash scripts/mainnet/40-ec2-start.sh`. This installs the service (port 8788, holdback 0,
   1-minute worker), adds `mainnet.16-4-100-95.sslip.io` to Caddy (backed up and validated first) and checks `/health`.
   The testnet service is untouched.
5. **Mac on mainnet:** `launchctl setenv GREMLO_SERVER https://mainnet.16-4-100-95.sslip.io`, then quit and reopen
   Gremlo (1.1.3 or later). To go back: `launchctl unsetenv GREMLO_SERVER`, then reopen.
6. **Pet (operator storage):** `OWNER=YOU PET=<name> bash scripts/mainnet/50-register-pet.sh`, then again with
   `CONFIRM_MAINNET=yes`. You approve one signature. Use the same name the Mac uses (Settings → Pet).
7. **Pair this Mac (no NEAR):** `OWNER=YOU PET=<name> CONFIRM_MAINNET=yes bash scripts/mainnet/60-pair-mac.sh`.
8. **Campaign (0.2 NEAR):** `BRAND=YOU LINE="…" bash scripts/mainnet/70-campaign.sh`, then again with
   `CONFIRM_MAINNET=yes`.
9. **The real flow:** turn sponsored lines on, start a Claude Code run, and let the sign show for 5 s. Within about a
   minute the worker settles: `ssh gremlo-ec2 journalctl -u gremlo-api-mainnet -f` shows `settle: … tx …`. The next
   hook makes the pet think on its new budget, and the log shows `charge: … tx …`.
10. **Proof:** put both tx hashes (`https://nearblocks.io/txns/<hash>`), the account ids and the code hash
    `5pu1xBnBucsruBkTV4jg5j9WBMk2w95nNySpz9E58RSZ` in README and PROOF.md, with the plain statements above.

Afterwards: raise `HOLDBACK_HOURS` to 24 in `/etc/systemd/system/gremlo-api-mainnet.service` once the first run is
proven (`sudo systemctl daemon-reload && sudo systemctl restart gremlo-api-mainnet`).
