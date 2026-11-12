# Notchi 1.0, round 3: the site, the notch, eggs and the Closet

Extends `NOTCHI_1.0_ROUND2.md`. Where they disagree, this file wins.
The canvas page **1.0 · round 3** is the visual reference. The working website prototype is in `web/`.

## 1. Packs v5: 31 rows

Sheets are 1536 × 6448. Rows 0–28 are unchanged; two rows are new.

| Row | Name | Frames | Use |
|---|---|---|---|
| 29 | wardrobe2 | 6 | preview poses: bow, flower crown, scarf, shades, cap, star clip |
| 30 | hatch | 8 | 0 rest, 1–2 wobble L/R, 3 crack, 4 crack all round, 5 glow, 6 burst, 7 hello |

New in `pet.json → notchi`:
- **`headAnchor[row][frame]`** is `[x, y, unitPx]` in cell px, or `null` where accessories hide. They hide on climb, evolve, peek, edgepeek, thrown and hatch.
- **`accessories`:**
  - `accessories.png` is 12 cells of 40 × 40 sprite units, at 1 px per unit, with the anchor at (20, 12).
  - Order: beanie, crown, headphones, party, wizard, glasses, bow, flower, scarf, shades, cap, star.
  - To draw one, scale the cell by `unitPx × petScale` and place its anchor on `headAnchor`.
  - Draw neck first, then face, then head. One item per slot.

Regenerate with `python3 tools/roster3.py`, which writes `packs3/`. It imports roster2.py, which imports roster.py.

## 2. Notch Live: twelve states

| State | Size | Trigger | Motion |
|---|---|---|---|
| rest | 190 × 32 | nothing | none |
| think | 210 × 32 | model thinking (between UserPromptSubmit and the first tool) | accent edge breathes, 1.6 s |
| peek | 290 × 36 | PreToolUse | eyes (row 14) and a pulse |
| live / ticker | 600 × 82 | hover or pin | tool chips slide in as they fire, timer |
| knock | 660 × 150 | PermissionRequest | two shakes (550 ms), then still |
| queue | 700 × (60 + 46 per agent) | 2 or more waiting | oldest first, max 4 rows |
| done | 520 × 82 | Stop | 46 confetti bits fall out, fold in 4 s |
| room | 540 × 230 | trackpad drag down on the notch | the pet's room: window, bowl, bed, hat rack; pet sits (row 18) or sleeps |
| egg | 290 × 36 | before hatching | egg wobbles per tool call, "warming up · N calls" |
| sleep | 250 × 34 | 23:00–06:00 or nap | closed eyes, Zzz drift out |
| visitor | 420 × 40 | team mode | a teammate's companion knocks before it walks out |
| focus | 290 × 36 | focus session | timer ring |

- **Priority:** knock > queue > visitor > done > ticker > peek > egg > focus > think > sleep > rest.
- **Gestures:**
  - hover: one size up
  - click: pin
  - drag down: room
  - two-finger swipe: next agent
  - drag a pet into the notch: send it home
  - long press: pause 30 min
  - ⌥↩ / ⌥⌫ / esc
- **Motion:** resize with bloom (420 ms, `cubic-bezier(.34,1.4,.5,1)`). Content fades in over 220 ms after the shape settles.
- **Reduce Motion:** 120 ms fades only. No shake, no confetti.
- Still no ads in the notch, ever.

## 3. Hatching

- **Pick an egg:** onboarding shows the three starter eggs (Notchi, Pip, Moss). The choice is the starter.
- **The egg arrives** on the first SessionStart: it drops out of the notch, and the notch's egg state shows a count.
- **Cracks come only from real hook events:**

  | Event | Frame | Note |
  |---|---|---|
  | each tool call | wobble (1/2 alternating) | |
  | 12th call | 3 | tick sound |
  | 25th call | 4 | |
  | 50th call | 5 | glow; waits for the next Stop |
  | that Stop | 6, then 7 | burst, hatch.wav and confetti |

- **Skip:** ⌥-click the egg hatches it now, with no penalty.
- **Certificate:** name, species, hatch time and first agent. Private until shared. Never a repo, path or prompt.
- **Unlocks** arrive as eggs in the notch with a one-line note and hatch as companions.
- No streaks, no daily check-ins, nothing to tap.

## 4. The Closet

- Twelve accessories in three slots: head ×9, face ×2, neck ×1.
- **Stars** are earned only. They can't be bought, gifted or sold, and no money is ever shown.

  | Earned for | Stars |
  |---|---|
  | each meal (with a receipt) | +1 |
  | first celebration | +5 |
  | every 5 approvals answered | +1 |
  | a finished focus session | +2 |
  | a teammate's review answered | +3 |
  | hatching day | +10 |

- **Prices:** party 5, beanie 10, scarf 10, star clip 12, bow 15, cap 15, glasses 20, headphones 20, flower crown 25, shades 25.
- **Milestone-only:** crown (100 meals), wizard hat (Elder).
- **Try on** is free and unlimited. Locked items show progress, never a nag.
- No packs, no random drops, no limited-time items.
- Sponsors never get accessories. Brands only get the plate.

## 5. The website (`web/notchi.html`)

A single page using Lenis 1.1.13, GSAP 3.12.5 and ScrollTrigger, with canvas sprites.

**Sections**

| Section | What happens |
|---|---|
| Hero | Physics pet: drop, drag, throw, bounce, dizzy, poke, cursor gaze, wander, yawn, sit |
| Velocity marquee | Moves with scroll speed |
| Notch Live | Pinned scrub (320%) through 8 states, with a typing terminal |
| Hatching | Pinned scrub (360%) with a real-count counter and confetti |
| Certificate | Live name input |
| Eggs and growth | Hover wobble; meal bar scrubs |
| Eight pets | Horizontal pinned rail; the page tints to each pet's colour |
| Closet | Real accessory layering with a star wallet (demo) |
| Money | Scroll-linked parade of plates |
| Privacy | Word-by-word fill |
| End | Goodbye from the notch |

**Rules**
- Every section reads with no motion.
- Reduce Motion turns off Lenis, physics and confetti.
- Works at phone width.
- Every figure is labelled example.

**Production port**
- Same structure in your web stack (Next.js or Astro).
- Keep the sprite renderer (`class Pet`) as a small module.
- Load `pet.json` for anchors instead of the inline table.
