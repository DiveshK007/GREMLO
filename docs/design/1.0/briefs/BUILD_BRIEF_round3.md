# Build brief, round 3 (after round 2's milestone 1)

1. **Packs v5.** Swap in `assets/pets/*` (31 rows, `accessories.png`, `headAnchor`). Loader: accept v3/v4/v5; hide accessories where headAnchor is null.
2. **Accessory layer (Mac).** One `CALayer` per slot above the sprite. Each frame, set its position from `headAnchor[row][frame]` × scale. Draw neck → face → head. Snapshot-test all 12 on all 8 species on idle frame 0.
3. **Notch Live states.** Add think, queue, room, egg, sleep, visitor and focus as in spec §2. Write the priority resolver as a pure function with table tests. Add the gestures (drag-down room, swipe agents, long-press pause).
4. **Hatching flow.** Egg picker in onboarding. Egg state machine driven by hook events (12/25/50 calls, then the next Stop). ⌥-click skip. The certificate is a share card rendered from data only. Unlocks arrive as eggs.
5. **Closet.** A stars ledger: append-only rows of `{reason, amount, receipt-or-event id}`, recomputed rather than trusted. Items with prices; crown and wizard are milestone-gated. Try-on preview. No purchase path involving money anywhere: add a test that fails if one appears.
6. **Website.** Port `web/gremlo.html` into the site repo. Keep Lenis + GSAP pinned at the same versions. Replace the inline anchor table with `pet.json`. Lighthouse: no layout shift from pins; respect Reduce Motion.

Definition of done is the same as round 2. Never fake: the wallet, counts and dates on the site are labelled examples.
