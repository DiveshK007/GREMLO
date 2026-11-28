# Rotating the operator key

A checklist to run by hand. `operator.gremlo.testnet` signs every write the server makes: `register_pet`,
`set_verified`, `settle_impressions`, `charge_compute` and `close`. The server reads its key from
`NEAR_OPERATOR_PRIVATE_KEY` in `/etc/gremlo/api.env` on the EC2 box, once at startup.

The plan: add the new key next to the old one, switch the server over, prove the new key signs a real tx, and only
then delete the old key. Until the last step, rolling back means putting the old line back and restarting.

Commands use the official `near` CLI (near-cli-rs), the same one `contracts-accounts/README.md` uses. They were not run
from this repo. If your version words a step differently, check `near account add-key --help`.

## Before you start

- [ ] **Keep it full access.** `register_pet` attaches a 0.01 NEAR storage deposit, and a function-call key can't attach a deposit.
- [ ] **Find a key you can sign with.** You need a key you can sign with today, either in your local keychain or in `~/.near-credentials`. It is needed to add the new key. List what's on the account:
      `near account list-keys operator.gremlo.testnet network-config testnet now`
      Write down every public key and which one the server uses. That's the one whose private key is in `api.env`.
- [ ] **Check health.** `curl -s https://16-4-100-95.sslip.io/health | jq '{ok, reasons, operator}'` shows `"ok": true`, with the balance above 0.5 NEAR.
- [ ] **Pick a quiet minute.** A restart in the middle of a think can lose that thought's `charge_compute` (the thought is served but not billed). Watch for a minute with no `think` or `charge:` lines first:
      `journalctl -u gremlo-api -f | grep -E "charge:|settle:|worker:"`
- [ ] **Hold off on pushes.** A push to `main` that touches `apps/server` or `packages/brain` restarts the service on its own. Don't push during the rotation.

## 1. Add the new key (on your laptop)

- [ ] Create a key pair and add it as full access in one step, saving the private key to a file only you can read:
      ```bash
      near account add-key operator.gremlo.testnet grant-full-access autogenerate-new-keypair \
        save-to-legacy-keychain network-config testnet sign-with-keychain send
      ```
      (`sign-with-legacy-keychain` if your signing key is in `~/.near-credentials`.) The new key is written to
      `~/.near-credentials/testnet/operator.gremlo.testnet/<new public key>.json`.
- [ ] Note the tx hash it prints, and check that `list-keys` now shows both the old and the new public key.

## 2. Put it on the server (EC2)

- [ ] `ssh` to the box, then edit the file with `sudoedit`, so the key never lands in shell history or a world-readable temp file:
      ```bash
      sudoedit /etc/gremlo/api.env
      ```
      Replace only the `NEAR_OPERATOR_PRIVATE_KEY=ed25519:…` line with the new `private_key` value from the JSON file.
      Keep the old line's value somewhere safe until step 5. Leave `NEAR_OPERATOR_ACCOUNT_ID=operator.gremlo.testnet` as it is.
- [ ] Check the file is still root-only: `sudo stat -c '%a %U' /etc/gremlo/api.env` prints `600 root`.

## 3. Restart

- [ ] `sudo systemctl restart gremlo-api`
- [ ] `sudo systemctl status gremlo-api --no-pager` shows `active (running)`.
- [ ] `journalctl -u gremlo-api -n 50 --no-pager` shows no startup error. A malformed key stops the start. A well-formed key that isn't on the account only fails at the first send, so step 4 still matters.

## 4. Verify

- [ ] `curl -s https://16-4-100-95.sslip.io/health | jq` shows `"ok": true`, `operator.account` = `operator.gremlo.testnet`, and `operator.balance` not null.
      This proves the server is up and reads the chain. **It does not prove the new key signs.**
- [ ] **Prove the new key signs.** Get the server to send one real tx, either of these:
      - a paired, fed pet thinks (start a Claude Code run on your Mac), and the log shows `charge: <pet> paid … tx <hash>`, or
      - the next worker pass settles queued views: `settle: campaign <id> paid … tx <hash>`.
- [ ] Open that tx on `https://testnet.nearblocks.io/txns/<hash>`. The signer is `operator.gremlo.testnet`, and the
      access key used is the **new** public key.
- [ ] If the log shows `InvalidAccessKeyError`, `AccessKeyDoesNotExist` or a signature error instead, roll back (below).

## 5. Remove the old key

Only after a tx signed with the new key has landed:

- [ ] ```bash
      near account delete-keys operator.gremlo.testnet public-keys <old public key> \
        network-config testnet sign-with-legacy-keychain send
      ```
      Sign with the **new** key, which is now in your legacy keychain.
- [ ] `near account list-keys operator.gremlo.testnet network-config testnet now` shows the new key and not the old one.
- [ ] `/health` is still `"ok": true`, and the next `charge:` or `settle:` line lands.
- [ ] Delete the copy of the old private key you kept in step 2.

## 6. Other copies

- [ ] `apps/server/.env` on any dev machine that talks to testnet as the operator: update it, or better, give local
      development its own operator account so the production key lives only on EC2.
- [ ] No CI workflow holds the key: `.github/workflows/` reads public RPC only.
- [ ] Log the rotation in `HANDOFF.md`: the date and the new public key. Never the private key.

## Rollback (any time before step 5)

1. `sudoedit /etc/gremlo/api.env` and put the old `NEAR_OPERATOR_PRIVATE_KEY` value back.
2. `sudo systemctl restart gremlo-api`, then repeat step 4.
3. Remove the unused new key with `near account delete-keys …` and the new public key.

After step 5 there is no rollback to the old key. Fix forward with a fresh key, starting again from step 1.
