# Notchi 1.0: build plan

Source of truth: `docs/design/1.0/` (base spec `NOTCHI_1.0_DESIGN.md`, then `ROUND2`, `ROUND3`, `ROUND4`; later rounds win; build briefs in `briefs/`).
Branch: `notchi-1.0` (from `near`). Push after every milestone. Each milestone lands with its tests.

Decisions (2026-11-13):
- **Human check:** World ID stays.
- **Approvals:** the notch, menu bar, phone and Watch may answer a `PermissionRequest`, with guards. Delete, push and spend need a click and get no shortcut. The terminal answer wins.
- **Out of scope for now:** Windows, Linux and the shared Rust core (teammates, after the Mac product ships).
- **iPhone and Watch:** built and tested in the simulator. Signing, push and TestFlight wait for an Apple Developer account.
- **Packages:** the "split into MIT repos" step stays in this monorepo as packages with their own LICENSE until production.
- **Never fake:** seeded or example data is labelled, and unknown values show `—`.

## Milestones

| # | Milestone | Spec | Status |
|---|---|---|---|
| 0 | Import design export, assets, generators; plan; rules | export README | done |
| 1 | Foundations: Mac package split (NotchiCore library + app + tests); pack loader v3–v6; 8 species with accents; sign plate (nine-slice kit, AD tab, never mirrored); accessory layer; anchors; backflip arc and moonwalk slide; old skins removed | D§1–3, R2§1–2, R3§1, R4§1 | done |
| 2 | Pets alive: idle scheduler, gaze, sit and perch, edge peek, physics (grab, throw, bounce, dizzy), social meetups, context (night, battery, offline), tool props | R2§3–6 | done (meetups and perching switch on with companions, M5) |
| 3 | Theme (System/Light/Dark, paper-safe accents, contrast test), sound (four levels, silence gate, voice rate limit), haptics | R2§7–8, HAPTICS | done (the gate's detectors land in M7) |
| 4 | Notch Live: 12 states, priority resolver, gestures, approval queue answering with guards, usage and cost readers, soft alerts, done and offline | D§5, R2§9, R3§2 | done (room, egg, visitor and focus content and the drag-down/swipe gestures arrive with their milestones) |
| 5 | One earner + companions per agent; hatching and eggs; growth stages from meals; Closet with the stars ledger; wardrobe; diary (opt-in); certificate | D§2,6–8, R3§3–4 | done (window perching, model-written diary entries and the certificate/diary share cards are open: perching needs the agent's window, the cards come with the postcard in M7) |
| 6 | Hook plumbing (test-runner matcher, git hooks with install/remove), bug hunt and jar, stuck detector, git moods, drop zone, session scrubber, dreams, tricks, seasons, meeting heads-up | R4§2–10 | done (open: `--global` git hooks via core.hooksPath come with the CLI in M8; PR-merged needs a GitHub connection; companions don't chase bugs yet and the bug flies to the pet; Show me focuses the first running terminal, not the exact window; approvals to the phone during meetings wait for M11) |
| 7 | The room and guestbook, focus mode, privacy ledger (screen-share duck, meetings, Focus, ⌥⌘P, export/delete), stream mode, weekly postcard | D§9, R2§12, R4§11–15 || done (open: a system Focus can't be read without the Focus Status entitlement, so only our own Focus sessions count; camera-in-use and browser screen sharing aren't detected (mic and Zoom/system recorder are); visits arrive through the M9 relay; the pet in the room is a still frame) |
| 8 | `notchi` CLI over the local socket, `notchi://` URL scheme, App Intents (Shortcuts), Raycast extension | R2§10 || done (open: Shortcuts only lists App Intents from a bundle with Xcode's Metadata.appintents, which the SwiftPM release script doesn't make yet, so Shortcuts uses notchi:// and `notchi` until then; the Raycast extension isn't type-checked here (no node_modules); `submit` arrives with the gallery in M9) |
| 9 | Server and web: plate lines 6–40 characters enforced in the console and the claim checks (R2 §2); brand A/B (4 lines, Thompson), moments, brand safety, signed hourly batches with a public log and `notchi verify`, money page; team relay; pet park; guestbook visits; creator tools and gallery | R2§11,13,15–16, R4§12,14 || done (open: the public log chains each signed P-256 sighting report rather than an hourly ed25519 batch per pet; domain and business-payment verification and the human line review are a process, not code; GitHub review/@-mention triggers for team visits need a GitHub connection, so visits are sent by hand; gallery image safety and look-alike checks are for the reviewers; the money page shows vault totals, and the fee stays a dash until published) |
| 10 | Website: full port of `web/notchi.html` into Next (hero physics and bug hunt, Notch Live scrub, hatching, eight pets, Closet, room, dreams, park, money, privacy), light mode switch | R3§5, R4§19 || done: the design page is the home page in its own route group (markup and CSS as is, its script in public/site/site.js after GSAP 3.12.5, ScrollTrigger and Lenis 1.1.13), the app pages keep their layout, the old home is /live (open: the site script still uses its inline anchor table instead of each pet.json, and the light-mode switch from R4 §19 isn't added) |
| 11 | Reach: VS Code/Cursor extension; iPhone app (Live Activity, lock-screen approvals, Dynamic Island, widgets); Watch complication | D§10, R4§16–17 | |
| 12 | Readable accounts: factory and purse contracts, function-call key limited to `pay_inference`, caps and allow-list | R4§18 || done: contracts-accounts (factory and purse, 13 unit tests incl. the Mac key's single method and the call that crosses the daily cap). Not deployed and not wired into the live flow, which still uses the vault's compute budget; Settings, Advanced would show the account id once it is |
| 13 | Copy review (no chain names in product copy), docs, README, full QA pass | all | |

## Tests the spec requires (tick as they land)

- [x] Plate snapshot at 1× and 2× for all 8 species; loader v3/v4/v5/v6
- [x] Accessories on all 8 species (idle frame 0)
- [x] Idle scheduler weights, quiet rules, day seed; gaze boundaries with hysteresis
- [x] Physics: restitution, bounce cap, dizzy threshold, door locked while held, impressions paused while held, Reduce Motion
- [x] Social roll and cooldowns; tool-prop matcher table
- [x] Contrast ≥ 4.5:1 for every accent on paper; sound silence gate
- [x] Haptics: every Mac moment has a recipe; rate limits; nothing during a share or with a line up
- [x] Notch Live priority resolver table; approval queue (risk rules, decision JSON, terminal answer releases); usage and cost estimate; hook-settings merge
- [x] Closet: no purchase path with money (a test that fails if one appears); stages, meals once per receipt, stars ledger, hatching table, unlocks, companions
- [x] Runner matcher; bug lifecycle; stuck normaliser; git force-push fixture and MERGE_HEAD watcher; drop-zone quoting; dreams, tricks, seasons, heads-up
- [x] Drop zone quoting and image pasteboard; stream mode turns the plate off and freezes sightings
- [x] Park payload is exactly `{id, name, species, stage, outfit}`; postcard text has no path, repo or currency
- [x] Purse: a function-call key can't transfer (the factory gives the Mac's key only pay_inference); caps reject the call that crosses them
