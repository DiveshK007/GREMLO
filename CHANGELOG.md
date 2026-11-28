# Changelog

## v1.1.1 (28 Nov 2026)

Fixes from an on-screen pass over 1.1.0. The first update delivered by the 1.1.0 updater.

- **The pet hid for hours after a screenshot.** macOS keeps `screencaptureui` running long after a screenshot, and the app took that as screen sharing: the pet stayed in the notch and the sponsored line stayed off. It now counts only while that process shows a window (the toolbar, the thumbnail, a recording's stop button).
- **Approval dot.** The menu bar icon shows an orange dot while an approval waits, for any agent. The 1.1.0 orange tint never showed: the menu bar draws icons in one colour.
- **Panel rows.** A long value no longer cuts off its label ("Compute b..."); Health reasons are short enough for one row; amber text is darker in Light; "Last think" shows the server's words instead of raw JSON; the Closet and Pet page rows have their full height again.
- **VoiceOver.** Theme, Go home after and Remind me are now radio groups VoiceOver can read and change; before, it couldn't see them at all.

## v1.1.0 (28 Nov 2026)

A Mac app that sets itself up and keeps itself up to date. The vault and the testnet deployment are unchanged.

- **Updates itself.** Sparkle 2.10.1, pinned by checksum. Each release carries an EdDSA-signed `appcast.xml`. The app checks once a day and installs on the next restart. Turn it off in Settings, General, Updates. "Check for updates" is in the menu bar panel. Sparkle checks every update against the key built into the app and clears the quarantine flag, so after the first launch no update needs Open Anyway. Builds from source have no updater and update with `install.sh`.
- **Still ad hoc signed.** There's no Apple Developer ID yet, so the first launch still needs Open Anyway. The release pipeline is ready for one: add the Apple secrets and it signs with the hardened runtime, notarizes and staples. Setup: [docs/RELEASE.md](docs/RELEASE.md).
- **First-run setup.** Five steps: welcome, your pet, pair this Mac, connect Claude Code, and a test event sent through the real hook that the pet answers. Each failure says why and has a Retry. Run it again from Settings, General.
- **Opt-in diagnostics.** Off by default (Settings, Privacy). When on: failure counts and crash signatures, at most once a day, unsigned and with no pet name, path or agent content. The server keeps no IP. "Show" displays the exact report.
- **Health in the panel.** It shows whether the server is reachable, whether this Mac is paired, whether views are counting (and if not, the first thing to fix), views on hold, to pay and paid today, and the compute budget with its share of each view.
- **Silent failures fixed.** A reinstalled or renamed Mac is now told it isn't paired; before, it looked paired while every view was refused. View refusals and stuck payments show in the panel. A pet whose payout account is missing no longer stops payments to the pets after it (server). Park joins say why they failed.
- **Polish.** The menu bar icon turns orange while an approval waits and dims when the server can't be reached, paused or in focus, and says so to VoiceOver. Plainer empty states. Every keyboard shortcut is listed in Settings, General.

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
