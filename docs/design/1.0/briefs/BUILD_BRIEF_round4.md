# Build brief, round 4 (after round 3)

Do these in order. Each step ships behind its own setting so it can be turned off.

1. **Packs v6.** Swap in `assets/pets/*` (39 rows) and `assets/props/`. Loader accepts v3–v6. Add the backflip jump arc and moonwalk slide in the animation layer, driven by `pet.json → arcs`.
2. **Hook plumbing.** Add the test-runner matcher and git events to the existing hook pipeline. `gremlo hook install git` / `remove git`, chaining existing hooks. Socket messages carry event names only.
3. **Bug hunt + bug jar.** Bottom-edge walker for bugs, chase/catch state machine (spec §2), squash on click. Jar count in the stars ledger's sibling table (counts, no streaks).
4. **Stuck detector.** Pure function over the event stream with table tests; notch card with the three buttons. It never acts on the agent.
5. **Notch utilities.** Drop zone (§5), session scrubber (§6), meeting heads-up via EventKit (§10).
6. **Pets alive.** Git moods (§4), dreams in the sleep state (§7), tricks with milestone unlocks and `gremlo trick` (§8), seasonal scenery (§9).
7. **The room.** Furniture spots and pet behaviours (§11), sharing the Closet's stars ledger. Then the guestbook (§12).
8. **Social.** Stream mode local server (§13, plate off, sightings frozen), the park service and page (§14, four fields only), weekly postcard renderer (§15).
9. **Reach.** VS Code/Cursor extension over the local socket (§16), Watch complication (§17).
10. **Readable accounts, optional.** Factory + purse contracts and the function-call key flow (§18). Copy review: no chain names anywhere in product text.
11. **Website.** Port `web/gremlo.html` changes (hero bug hunt, room, dreams, park). Keep Lenis 1.1.13 and GSAP 3.12.5.

Definition of done is the same as round 2, plus the tests in spec §20. Never fake: example wallets, sample pets, sample visits and sample counts are labelled; unknown balances show `—`.
