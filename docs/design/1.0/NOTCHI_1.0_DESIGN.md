# Notchi 1.0 — production design spec

A pet for every agent. Eight original species that live behind a hidden door in
the MacBook notch, react to coding agents, grow up on what they earn, and pay for
their own thinking by holding one sponsored line while the agent works.

The canvas page **Notchi 1.0** is the visual source of truth. This file is the
written contract both the Mac and web builds follow.

---

## 1. System

### The rule
The UI is ink and paper. Nothing in the chrome has a colour of its own.
**The active pet lends the interface its signature colour.** Pip makes the UI
yellow, Byte makes it cyan. Everything else is restraint.

### Neutrals (dark first)
| Token | Hex | Use |
|---|---|---|
| Ink | `#0B0B0B` | app background |
| Carbon | `#141414` | panels, popover |
| Graphite | `#1F1F1F` | controls, selected tab |
| Bone | `#E9E6DF` | light-mode panels |
| Paper | `#F4F2ED` | light-mode background, text on ink |

Text and rules use the opposite neutral at `.85 .62 .45 .14`. No greys of their own.

### Adaptive accent — measured WCAG
| Pet | Accent | On ink | Paper-safe (text on paper) |
|---|---|---|---|
| Notchi | `#FF5A3C` | 6.4 | `#C1442D` |
| Pip | `#FFC93C` | 12.8 | `#876A1F` |
| Moss | `#8FD14F` | 10.7 | `#52792D` |
| Gloop | `#2ED3B7` | 10.4 | `#1B7C6B` |
| Byte | `#4CC9FF` | 10.4 | `#2C7696` |
| Puff | `#8FA8FF` | 8.6 | `#5B6BA3` |
| Wisp | `#B48CFF` | 7.6 | `#7C60AF` |
| Tako | `#FF7AB6` | 8.2 | `#AA5179` |

Accent on ink, and ink text on an accent button, both pass for every pet.
On paper, text uses the paper-safe shade; fills and the pet keep full colour.
(The v2 doc's "7.4:1" figure for Signal on ink was wrong — it is 6.4:1.)

### Type
```
Display  Bricolage Grotesque 800 · -0.04em · lh .9 · 64-230px
Heading  Inter 600 · -0.02em · 22-34px
Body     Inter 400 · 15-17px · max 62ch
Mono     JetBrains Mono 500 · 10-13px · IDs, hashes, labels only
```

### Shape
Radius `0` layout blocks · `6` controls · `14` popover and phone surfaces ·
Notch Live inherits the hardware curve. One shadow in the product, on floating
surfaces only. Space `4 8 12 16 24 40 72 120`.

### Motion tokens
| Token | Value | Who uses it |
|---|---|---|
| snap | 160ms `cubic-bezier(.2,.8,.2,1)` | chrome |
| settle | 280ms `cubic-bezier(.3,1,.4,1)` | chrome |
| bloom | 420ms `cubic-bezier(.34,1.4,.5,1)` | Notch Live, door |
| bounce | spring stiffness 300 / damping 14 | the pet only |
| drift | 900ms linear | roaming |

Reduced motion: hold frame 0 of each state, crossfade states in 120ms.

---

## 2. The roster

| Species | Kind | Unlock | Voice | Signature move · fires on |
|---|---|---|---|---|
| Notchi | bean | starter | plain-spoken: "on it." | big stretch · Stop after a run > 20 min |
| Pip | bird | starter | chirpy: "tests passed!" | chirp · PostToolUse, tests pass |
| Moss | sprout | starter | calm: "slow and steady." | bloom · every 10th meal |
| Gloop | slime | a session over an hour | patient: "mhm. still here." | split · Stop with zero failures |
| Byte | robot | 1,000 tool calls watched | terse caps: "EXEC OK." | glitch · PostToolUse, tests fail |
| Puff | cloud | the agent's first failed run | soft, melancholy | rain · StopFailure |
| Wisp | flame | any pet thriving 7 days | quiet, poetic | flare · a meal that raises mood |
| Tako | octopus | secret: poke a pet to a stomp, 50 times | cheeky | ink squirt · 5th click in 6s |

None are for sale. None unlock from daily app opens or streaks.
The voice only tunes the model prompt for bubbles and the diary. A bubble
appears only when the model returned text, with a request ID.

### One earner, many companions
One verified person gets **one earner**: the pet that holds sponsored lines and
has a payout address. Every other running agent gets a **companion** — an
unlocked species with all animations, but no sign and no wallet. This keeps
"one human, one paycheck" intact while showing one pet per agent.

---

## 3. Sprite packs

`assets/pets/<id>/{pet.json, spritesheet.webp}` — eight folders.
Codex desktop-pet layout extended to **15 rows**: cell `192 x 208`, 8 columns,
frames left-aligned, trailing cells transparent, feet on a baseline at y=194.
`pet.json` carries `notchi.rows` with every row's index and frame count, and
`notchi.accent`.

| Row | Name | Frames | Base fps | Trigger |
|---|---|---|---|---|
| 0 | eat | 6 | 6 | a meal settles (top-up confirmed) |
| 1 | walk | 8 | 8 | idle roam |
| 2 | climb | 8 | 8 | going home (pre-rotated for the right wall) |
| 3 | greet | 4 | 5.5 | UserPromptSubmit, after the door |
| 4 | celebrate | 5 | 10 | Stop |
| 5 | idle | 8 | 2.4 | 0-3 idle loop · 4 hungry · 5-6 asleep · 7 alert |
| 6 | sign | 6 | 5 | PreToolUse, drifts at 0.4 |
| 7 | flag | 6 | 10 | PermissionRequest |
| 8 | fail | 6 | 7 | StopFailure |
| 9 | hover | 4 | 3.5 | cursor over the pet's alpha |
| 10 | annoy | 6 | 10 | clicks: 1-2 frame 0, 3-4 frames 1-2, 5+ frames 3-5 |
| 11 | special | 4 | 4 | species signature move |
| 12 | evolve | 6 | — | 0 egg · 1 cracked · 2 hatching · 3-4 hatchling · 5 elder |
| 13 | wardrobe | 6 | — | 0 beanie · 1 crown · 2 headphones · 3 party · 4 wizard · 5 glasses |
| 14 | peek | 4 | 2 | Notch Live compact (anchored to cell top) |

Mood scales the rate, never the frames: thriving ×1.25, stable ×1, hungry ×0.6.

The pixel sign board ships with placeholder lines. The app draws the real
campaign text on a plate the pet holds (paper fill, 2px ink outline, 11-12px
Inter 600). Never mirror the plate when the sprite flips.

`tools/roster.py` regenerates every pack: `python3 roster.py` writes `packs/`.
Species are data at the top of the file: profile, limbs, decor, palette.

---

## 4. Behaviour

### Priority (higher wins, lower resumes after)
1. Needs approval
2. Holding the line
3. A real say bubble
4. Celebrate or trip
5. Signature move
6. Noticed you / annoyed
7. Idle, walk, sleep

Loops end on their next frame boundary. One-shots finish unless something
above them arrives.

### The hidden door (~0.4s, bloom)
Invisible by default. Fades and scales in, glows the accent, swings open,
closes one frame after the pet has crossed, fades out. Locks on SessionEnd.

### Cursor
Overlay is click-through. A global mouse-moved monitor hit-tests the pet's
**alpha**, not its frame, and flips `ignoresMouseEvents` only while inside.
Annoyance counter decays to zero after 6s without a click. Cosmetic only;
never touches money or hooks.

### Window perching
A companion may walk onto the title bar of its own agent's window and follow
it when dragged. The earner stays on the screen edges.

---

## 5. Notch Live
No sponsored lines in the notch, ever.

| State | Size | Trigger | Content |
|---|---|---|---|
| rest | 200 x 32 | none | nothing |
| peek | 290 x 36 | PreToolUse | pet eyes (row 14) left, pulse dot right |
| live | 600 x 80 | hover or pinned | tool, agent, count, elapsed, activity bars |
| approval | 660 x 150 | PermissionRequest | command, Deny · Always allow · Allow once |
| split | 560 x 36 | two agents | one pet each side of the camera |
| done | 500 x 80 | Stop, folds in 4s | duration, tools, approvals, errors, earned |
| offline | 360 x 36 | network unreachable | "Can't reach the network · sleeping safely" |

Keys: hover opens, click pins, ⌥↩ allow once, ⌥⌫ deny, esc folds.

---

## 6. Growing up
A **meal** is one real top-up of the pet's own compute balance, paid from
earnings, with a receipt. It is the only unit of growth.

Egg (until the first SessionStart) → Hatchling (0-9 meals) → Buddy (10-49) →
Elder (50+). Stages never go backwards; hunger never shrinks a pet. Elder adds
reading glasses and a longer diary, no advantage. The progress bar fills only
with meals that each have a receipt.

## 7. Wardrobe
A hat layer drawn on the head, so all animations keep working. Unlocked by
milestones, never bought: beanie 10 meals · headphones 10 hours of sessions ·
party hat first celebration · glasses 25 approvals answered · crown 100 meals ·
wizard hat Elder. Locked items can be tried on; show the requirement and
progress, never a price.

## 8. Diary (opt-in, off by default)
Written once, after the day's last session, in the pet's voice, from hook
events only (tool names, counts, outcomes). Never code, never prompts. File
paths only if allowed. Private until shared. The share card carries the line,
the numbers and the pet — no file names, no repo.

## 9. Privacy ledger
| What | Leaves the Mac |
|---|---|
| Code, prompts, diffs | never read |
| Screen contents | never read |
| File paths, repo names | stay local |
| Stack, for line matching | stays local; every pet gets the same list and picks locally |
| Tool names and counts | only for the diary, if on |
| Impression counts | yes, signed, a number per campaign |
| Identity | one anonymous proof of personhood |

Always on, no setting: every pet ducks into the notch the moment the screen is
shared or recorded. Also: meetings (mic/camera in use or a busy calendar
event) → sleep; Focus → home; full screen → hidden; max 12 lines an hour,
never the same brand twice in a row. ⌥⌘P pauses everything. Export and delete
are one button each.

## 10. Phone and Watch
Live Activity while an agent runs; actionable approval on the lock screen
(Face ID); Dynamic Island compact (eyes + timer) expanding to ask; widgets
(today, agents, asleep after hours); Watch approval.

## 11. Never fake
- No mocked balances, request IDs, receipts or payments in a real flow.
- Seeded data is labelled seeded on screen.
- A dash means unknown. Never a zero — a zero is a claim.
- The model never authorises a payment; a deterministic budget check does.
- If the network is unreachable, stop and say so. Never invent a decision.
- User-facing copy names no chain. IDs and hashes are the only jargon allowed.
