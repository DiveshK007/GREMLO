# Changelog

## v1.0.2 (23 Nov 2026)

Mac app polish. Nothing changed in the web app, the API or the contract.

- **One surface style.** The notch, the menu bar popover and the sign share one set of numbers (`Surface+Mac.swift`): a glass fill where black is not required, a 1 pt edge highlight, a soft shadow and an optional glow.
- **Notch springs retuned.** Opening now takes about 220 ms (was about 140) with about 3% overshoot, closing about 190 ms (was about 130) with none. The old values are in `NOTCH_FEEL.md` if you want them back.
- **Progress wings.** Two slim strips beside the notch while an agent runs, then one green glow when it finishes (red, no glow, if it failed). No percentage is shown, because a run has no known length.
- **Pomodoro.** Off by default, in Settings, Privacy, Focus. 25 minutes of focus and a 5-minute break, four blocks, on top of the existing Focus session. Each finished block still earns 2 stars. `GREMLO_POMODORO_FAST=1` shortens it for testing only.
- **Bops to music.** The pet now bobs along, not only the notch. Off under Reduce Motion. The permission text says exactly what is read: whether something is playing, with the track name dropped.

## v1.0.1 (23 Nov 2026)

Changes since v1.0.0.

- **Hosted by default.** The Mac app and the `gremlo` CLI talk to the hosted server and open pages on gremlo.vercel.app. `GREMLO_SERVER` and `GREMLO_WEB` still override.
- **For judges.** A guided tour at `/experience`, [JUDGE.md](JUDGE.md) with the two-minute path, the simulated parts and the known limits, and videos hosted on the site.
- **`npm run verify:public`.** Checks the ten final-run transactions, the vault's code hash and `/stats` against public NEAR RPC. No API key or `.env`.
- **[SECURITY.md](SECURITY.md).** The key model, the vault's full-access key and the plan to lock it, and how to report an issue.
- **Web.** A production build with no env falls back to the hosted API. A payment is never shown without a tx hash. A campaign whose hooks fail to save can be retried. Plain contract errors. The brand page is split into components and hooks.
- **Server.** The API answers 400 to malformed URLs (the proxy in front of it still resets HTTP/2 requests with a bad percent escape). State-changing calls are POST. Settlement has a cooldown and a per-visitor limit. The store is written atomically and pruned. `/health` reports real problems and `/livez` is the liveness check.
- **Mac app.** The local hook server needs a per-install secret and refuses browser requests.
- **Contract.** `charge_compute` refuses the same completion id twice in a row for a pet. It is in the repo and tested, and is **not deployed**: `vault.gremlo.testnet` still runs the code from v1.0.0.
- **Tooling.** ESLint, Prettier (advisory), SwiftLint, and a server typecheck in CI.

## v1.0.0 (16 Nov 2026)

First release: the notch pet for macOS, the web app, the API and the NEAR testnet vault.
