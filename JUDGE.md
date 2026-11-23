# For judges

Two minutes. No Mac, no wallet, no API key.

1. **The tour.** Open [gremlo.vercel.app/experience](https://gremlo.vercel.app/experience). It shows the pet, the money loop and live testnet numbers read from the API.
2. **The live page.** Open [gremlo.vercel.app/live](https://gremlo.vercel.app/live). It has the line the pet holds right now and every "charged on chain" link. Each link is a `charge_compute` call on `vault.gremlo.testnet` that carries a NEAR AI completion id.
3. **The API.** `curl https://16-4-100-95.sslip.io/stats` returns campaigns, settled views, NEAR paid and NEAR charged for AI. `curl https://16-4-100-95.sslip.io/health` says whether the server and its worker are healthy.
4. **The proof, checked by a script.** Needs Node 22.9 or newer.

   ```bash
   git clone https://github.com/DiveshK007/GREMLO.git && cd GREMLO/apps/server
   npm ci && npm run verify:public
   ```

   It reads public NEAR testnet RPC only. It checks that each of the ten transactions in the final run succeeded, that the vault's code hash is the one that ran, and that `/stats` agrees with the vault's own totals. It exits 0 when all 15 checks pass and 1 when any fails. The inputs are in [`apps/server/fixtures/public-proof.json`](apps/server/fixtures/public-proof.json); the same hashes, with what each one did, are in [PROOF.md](PROOF.md).

The full walkthrough video (4:40) is at [gremlo.vercel.app/walkthrough.mp4](https://gremlo.vercel.app/walkthrough.mp4).

## What is simulated

- **World ID.** The final run used the World ID simulator (the staging environment), not a real Orb or World App proof. No real person was verified.
- **Seeded data.** Anything seeded is labelled as seeded on screen. `/stats` reports `seeded: false` for the live numbers.

Everything else in the final run is real: the transactions are on NEAR testnet, and the NEAR AI completions carry TEE signatures (`npm run verify <completion_id>` in `apps/server` checks one, and needs a NEAR AI key).

## What `verify:public` does not check

- Who signed a view, or whether a person was at the screen. Views are reports signed by a Mac's Secure Enclave key and checked by the server; that log is on the campaign page, not in this script.
- The NEAR AI completions. That check needs a NEAR AI key.
- That the deployed code matches this repo's source. The code hash matches a local `cargo near build` of `contracts-near`; the script only compares it to the hash that ran.

## Known limits

- **Testnet only.** Nothing is on mainnet. The money is testnet NEAR.
- **The app is Mac-only.** The notch pet runs on macOS 13+. The server, web app, brain and contracts build on Linux and macOS.
- **Views are settled by the operator.** The server's operator key calls `settle_impressions` and `charge_compute`. The contract limits what it can pay (a campaign's budget, a pet's daily compute cap), but you are trusting the operator to report views honestly. See [SECURITY.md](SECURITY.md).
- **The vault has a full-access key.** The deployer still holds it on `vault.gremlo.testnet`. Whoever holds it can replace the contract code. The plan is to remove it before mainnet; see [SECURITY.md](SECURITY.md).
- **AI is billed at a fixed NEAR rate per tier**, not the real USD cost, and the operator holds the NEAR AI credits.

The README's [What's real](README.md#whats-real) table has the rest.
