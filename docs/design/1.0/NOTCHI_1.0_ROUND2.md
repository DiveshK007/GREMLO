# Notchi 1.0, round 2: spec addendum

This adds to `NOTCHI_1.0_DESIGN.md` from the first export. Where they disagree, this file wins.
The visual source of truth is the canvas page **1.0 · round 2** (16 boards). The **Notchi 1.0** page now uses the new sheets too.

---

## 1. Sprite packs v4: 29 rows

`assets/pets/<id>/` holds `spritesheet.webp` (lossless, ~15 KB), `spritesheet.png`, `signkit.png` and `pet.json`.
Cells are 192 × 208, 8 columns, feet on y=194. Rows 0–14 keep the Codex layout, so Codex can still read a pack. Rows 15–28 are new.
The sheet is 1536 × 6032 px.

| Row | Name | Frames | fps | Trigger / rule |
|---|---|---|---|---|
| 0–14 | as round 1 | | | unchanged except 1, 2 and 6 below |
| 1 | walk | 8 | 8 | **redrawn**: contact, down, passing, up, with arm swing. Floaters (Puff, Wisp) bob; Gloop oozes |
| 2 | climb | 8 | 8 | **redrawn**: hand over hand, pre-rotated for the right wall |
| 6 | sign (pixel board) | 6 | 5 | **fallback only**, used when the sign kit can't be drawn |
| 15 | turn | 4 | 10 | reaching a wall: front, glance, side, back |
| 16 | startstop | 6 | 12 | before a roam (crouch, push) and after it (overshoot, settle) |
| 17 | gaze | 5 | none | pick a frame by cursor offset: < −150, −150…−40, ±40, 40…150, > 150 px. 12 px hysteresis. Only within 300 px; back to idle after 3 s of no movement |
| 18 | sit | 4 | 3 | on a window title bar or screen edge after 2 min idle, legs dangling. Rides the window if it moves |
| 19 | edgepeek | 4 | 4 | **anchored to the cell's left edge**. Slides in from the screen edge after hiding (share ends, full screen exits, meeting ends) |
| 20 | yawn | 4 | 3 | 10 min with no agent event |
| 21 | grabbed | 4 | 8 | held by the cursor (press ≥ 150 ms) |
| 22 | thrown | 4 | 16 | **centre-anchored**, quarter turns while airborne |
| 23 | land | 6 | 10 | 0 squash, 1 stretch, 2–3 dizzy (hard landing only), 4 settle, 5 recover |
| 24 | social | 6 | 8 | 0 wave, 1 raise, 2–3 high-five, 4–5 run (chase) |
| 25 | tools | 6 | none | pick by tool: 0 wrench, 1 magnifier, 2 flask, 3 terminal, 4 globe, 5 notepad |
| 26 | night | 4 | 2.4 | nightcap, 23:00–06:00 local |
| 27 | focus | 4 | 2 | focus session, breathing |
| 28 | hold | 6 | 4.5 | **holding the line**: both arms up, sign kit drawn overhead |

`pet.json → notchi` adds:
- `rows`: index and frame count for all 29 names.
- `signRect[i]`: `[x, y, w, h]` of the paper face in row 6, frame i (cell px). Only needed for the fallback.
- `plateAnchor[i]`: `[x, y]`, the **bottom-centre** of the plate for row 28, frame i, in cell px at full scale.
- `signKit`: `{path, size:[20,11], slice:{top:3,right:4,bottom:3,left:4}, scale:3}`.
- `anchors`: `{edgepeek:'left', thrown:'centre', peek:'top'}`. Every other row is feet-anchored.

Regenerate everything with `python3 tools/roster2.py`, which writes `packs2/`. It imports `roster.py` and doesn't edit it.

## 2. The sign kit

- Each species has a 20 × 11 px nine-slice: species-coloured end caps on a 1 px ink frame, with a paper face that stretches. Slices are 3 top and bottom, 4 left and right.
- Draw the kit with nearest-neighbour scaling. One kit pixel = `max(3 px, one sprite unit)`, and always a whole number of pixels.
- Text is Inter 600, 3.7 kit px tall (11 px at real size). Ink on paper is 17.4:1. Lines are 6–40 characters; the console enforces the limit. Never truncate or scroll a line.
- **Pose:** row 28, plate held overhead. The face is never covered.
- **Position:** the plate's bottom-centre sits at `plateAnchor` × pet scale. The plate doesn't bob; the pet bobs under it. The sprite may flip; the plate never mirrors.
- **Disclosure:** a small `AD` tab on the plate's top-right corner. Hover opens a card with the sponsor and "why this line". VoiceOver reads "Sponsored, <brand>: <line>".
- **Fallback:** at accessibility text sizes where the plate would be too big, use row 6 and show the line in the menu bar instead.
- CSS reference: `.sign` in `tokens.css`. On the Mac, draw a 9-slice `NSImage` (`capInsets`) with `NSAttributedString` on top.

## 3. Idle scheduler

- Fire one micro-behaviour every 25–45 s, chosen by weight: sit 3, yawn 2. Gaze runs instantly whenever the cursor is near.
- Seed the RNG per day.
- Never fire while holding the line, while an approval is waiting, in a meeting, or during a screen share.
- Nap after 15 min idle, or 5 min at night. Any agent event wakes the pet.
- Drive frames from timers on frame boundaries, never a 60 fps loop. Target under 0.5% of one core.

## 4. Physics

| Setting | Value |
|---|---|
| Gravity | 2,400 px/s² |
| Restitution | 0.35 |
| Max bounces | 3 |
| Floor friction | 0.8 |
| Release speed cap | 3,000 px/s |
| Dizzy threshold (impact speed) | 1,800 px/s |

- A grab needs a press of at least 150 ms, so ordinary clicks still feed hover and annoy.
- Picking up the earner lowers the sign and pauses impression counting until the pet is back on its feet.
- The door locks while a pet is held, so it can't be thrown into the notch. Dropping a pet on a title bar perches it there.
- Reduce Motion: no flight. The pet fades out and fades back in where it was dropped.
- Throwing a pet ten times in a minute makes it sulk (annoy row). This is cosmetic only.

## 5. Social

- **Trigger:** two free pets within 60 px of each other, walking toward each other.
- **Roll:** wave 100%, then high-five 35%, then chase 15%.
- **Limits:** a 10 min cooldown per pair and 6 meetups an hour in total. Same quiet rules as the idle scheduler.
- The earner only joins when it isn't holding a line. A visiting pet (team mode) only waves.

## 6. Context

| Signal | Behaviour |
|---|---|
| 23:00–06:00 | night row, naps sooner |
| First session of the day | species signature move, once |
| Battery < 20% and unplugged | sits more, half frame rate; < 10% goes home and sleeps; plugged in → one hop |
| Offline | sleeps; no lines, no meals; Notch Live offline state |
| Meeting / Focus / screen share | home (screen share always wins) |

**Tool props** are matched locally from `tool_name`:

| Prop | Claude Code | Codex | Cursor |
|---|---|---|---|
| wrench | Edit, Write, MultiEdit | apply_patch | edit_file |
| magnifier | Read, Grep, Glob | read, search | read_file, grep_search |
| flask | Bash whose first word is a test runner | shell, test runner | run_terminal_cmd, test runner |
| terminal | Bash, anything else | shell | run_terminal_cmd |
| globe | WebFetch, WebSearch | web_search | web_search |
| notepad | TodoWrite | update_plan | todo_write |

- The test-runner list is local: pytest, jest, vitest, go test, cargo test, forge test, npm/pnpm/yarn test, mocha, rspec.
- The command text never leaves the Mac.
- An unknown tool gets no prop.
- The earner shows props only between lines.

## 7. Light mode

- Background Paper `#F4F2ED`, surfaces Bone `#E9E6DF`, text Ink at .85 / .62 / .45, rules at .14.
- Accent fills keep full colour. Accent text uses the paper-safe shade from the round 1 table.
- The notch and Notch Live are always `#000`.
- Pets and sign kits never change.
- The floating-surface shadow in light mode is `0 20px 50px rgba(11,11,11,.18), 0 0 0 1px rgba(11,11,11,.08)`.
- Settings offers System · Light · Dark. The website gets the same switch.

## 8. Sound (`assets/sounds/`, 44.1 kHz, 16-bit mono WAV)

**Levels**

| Level | What plays |
|---|---|
| Off | nothing |
| **Approvals only (default)** | the approval chime |
| Pet sounds | adds voices, celebrate, fail, meal, door, hatch, offline, focus |
| Everything | adds whoosh, thud, boing, dizzy, poke-1…5, stomp, high-five, yawn, snore |

- Sounds are silent during screen share, meetings, Focus and full-screen video, at every level.
- Volume follows the system alert volume.
- **The sponsored line never makes a sound.**
- Voices: `voice-<species>-{say,happy,grumpy}.wav`. Play one only alongside a real model bubble, at most once every 20 s.
- Event map:

  | File | Event |
  |---|---|
  | approval | PermissionRequest |
  | allow, deny | the answer |
  | door-open, door-close | the door |
  | celebrate | Stop |
  | fail | StopFailure |
  | meal | a meal settles |
  | hatch | the egg hatches |
  | whoosh, thud, boing, dizzy | physics |
  | poke-n | click n |
  | stomp | 5th click in 6 s |
  | high-five | meet |
  | focus-start, focus-end | focus sessions |
  | yawn, snore | snore at 30% volume |
  | offline | network lost |

- Regenerate with `python3 tools/sounds.py`.

## 9. Notch Live: cost and queue

- **Live + cost (600 × 80):** shows `$0.42 est` and the token count on the right. The Done state shows the run's cost next to "<pet> earned X".
- **Sources:**
  - Claude Code: token usage in the transcript that `transcript_path` points to.
  - Codex: its usage events.
  - Cursor: not exposed, so show `—`.
  - Cost is tokens × a bundled price table, always labelled est. No data means a dash, never $0.00.
- Cost never leaves the Mac.
- **Soft alerts** at user-set amounts per run or per day: an amber pulse. Notchi never stops an agent.
- **Queue (700 wide, grows by one row per waiting agent, max 4 shown):**
  - Oldest first. Keys: ⌥↩ allow the top item, ⌥↓ next, ⌥⌫ deny.
  - Commands that delete, push or spend get no keyboard shortcut; they need a click.
  - Notch, menu bar and phone stay in sync. If a request is answered in the terminal, its row greys out and leaves.

## 10. CLI, Shortcuts, Raycast

The `notchi` CLI talks to the app over a local Unix socket (`~/Library/Application Support/Notchi/notchi.sock`). Commands:

| Command | Does |
|---|---|
| `status [--json]` | pet, earner state, agents |
| `say "<text>"` | shows your text in a bubble |
| `pause [dur]`, `resume` | pets home, lines off, counters frozen |
| `focus <dur>` | starts a focus session |
| `pet <species> [--agent x]` | sets the species for an agent |
| `celebrate` | plays celebrate once |
| `hook install <agents…>` | installs the hooks |
| `log [--today] [--json]` | the day's events |
| `validate <dir>`, `preview <dir>`, `submit <dir>`, `new <name>` | creator tools |

- `say`: up to 80 characters, at most once every 10 s, skipped during screen share. The bubble is **outlined and tagged "you"**. Model bubbles are filled and show the request ID on hover.
- No command can spend, pay, change the payout address or approve a risky command.
- URL scheme: `notchi://say?text=…`, `notchi://pause?min=30`, `notchi://focus?min=25`.
- Shortcuts (App Intents): Pause for N min · Start focus for N min · Make the pet say · Get status.
- Raycast extension: Pause pets · Start focus · Say something · Status · Answer next approval.

## 11. Team mode

- **Opt-in on both sides** with a team code.
- **Triggers:** a review request, an @-mention in a PR comment, or a manual "go say hi".
- **The visit:** your *companion* walks off your screen edge and appears on the teammate's screen holding the kit plate "PR #482 · review?". Clicking it opens the URL. It waits 2 min, then goes home.
- **Limits:** 3 visits an hour per recipient. A visit waits through the recipient's meetings, Focus or screen share, and expires after 30 min.
- **Relay payload:** team id, sender handle, species, PR number, PR URL. Nothing else, kept 24 h. The relay is open source and self-hostable.
- The earner never visits, and no sponsored line ever appears on someone else's screen.

## 12. Focus

- Durations: 25, 50 or 90 min. Start with ⌥⌘F, the CLI or Shortcuts.
- During a session one pet meditates (row 27) and Notch Live shows a 290 × 36 timer ring. Approvals still come through; everything else waits.
- **Lines are off** for the whole session, and the earner doesn't earn. The menu bar says so.
- No streaks, no badges. Ending early is allowed, with no guilt screen.
- A system Focus can start a session, if the user allows it.

## 13. Community species

- **Flow:** `notchi new` → `validate` → `preview` → `submit` (a PR to `notchi-pets`, or upload on the web) → review → gallery.
- **The validator checks:** pet.json, sheet size and 29 rows, frame counts, empty trailing cells, the y=194 baseline, ≤ 16 colours, the kit size and slices, a margin of at least 2 px, and no letters on boards.
- **Moderation:**
  - Machines: format, image safety on every frame, look-alike checks against known characters, mascots and logos, and text detection.
  - People: two reviewers who play every row. Target: two working days.
  - Three reports pause new hatches of a species while it is re-checked. Pets already hatched keep working.
- Only reviewed species can be earners.
- **Codex import:** each Codex row maps to the Notchi row with the same index. Fallbacks: climb → walk rotated; gaze → idle frame 0; land → fail 0–1; no tools → no props; no hold → can't be the earner. Imports stay local as companions and can't be submitted unless the importer made the art.
- Creators get credit, not a storefront. Nothing is sold.

## 14. Platforms

- **macOS:** the notch. Macs without a notch and external displays get a top-centre pill.
- **Windows:** a "taskbar burrow" door by the tray (or the top pill). Layered click-through window per display, WinRT capture detection.
- **Linux:** the top pill. Full overlay on X11 and on Wayland with wlr-layer-shell; anywhere else, a small always-on-top window.
- **Shared Rust core:** hook server, matcher, budget check, receipts, sprite timing.
- **Hard rule:** if a platform can't reliably detect screen sharing, its pets never hold lines.

## 15. Brands

- **A/B testing:**
  - Up to 4 lines per campaign.
  - Even traffic until each line has 2,000 sightings, then Thompson sampling on "opened" (the "what's this?" link) per sighting, rebalanced hourly. Floor 5% per line.
  - Clicks on the pet never count.
- **Moments:**
  - Lines are tagged `tests | deploy | long run | any`.
  - The moment is computed on the Mac from the tool kind and the local stack. Every pet gets the same campaign file and picks locally.
  - Brands see sightings per line, and per moment only for buckets with at least 50 distinct pets.
  - Never show a line during fail, celebrate or an approval.
- **Safety:**
  - Verify the domain and a business payment.
  - Every new line gets an automated policy check plus human review (target: one working day).
  - Closed categories: gambling, adult, weapons, political and issue ads, health claims, payday loans, speculative investments.
  - Menu bar offers "Not for me" and "Report". 3 reports per 1,000 sightings auto-pauses a line.
  - Owners can block brands or categories.
- **Sponsored hats: no.** The wardrobe is earned, never sold, and brands only ever get the plate.

## 16. Trust

- **Open source (MIT):** `notchi-hook`, `notchi-matcher`, `notchi-budget`, `notchi-relay`, `notchi-pets` (code).
  - The species art and the name stay proprietary.
  - Builds are reproducible. Settings → About shows the running hook's hash next to the tagged release hash.
- **Money:**
  1. The brand pays per 1,000 sightings.
  2. The platform takes its fee: **rate published before launch; until then show "—"**.
  3. The rest goes to the pet's balance.
  4. Meals come first, each with a receipt.
  5. Surplus above a small reserve goes to the owner weekly.
  6. Unspent budget is refunded to the brand.
- **A sighting counts** only when the plate is fully visible for ≥ 2 s, the screen is unlocked, not shared and not recorded, there was input in the last 60 s, and the pet is under 12 lines/hour with no repeat brand.
- **Proofs:**
  - Each pet signs an hourly batch: `{campaign, hour, count per line, anon pet id, prev hash}`, signed with a device ed25519 key.
  - The server verifies the signature, the one-person proof and the limits, then appends the batch to the campaign's public log.
  - `notchi verify <campaign>` replays the log and must match the bill.

## Never-fake, still

- Every figure on the boards is seeded and labelled. Ship none of them.
- A dash means unknown.
- The model never authorises money.
- When offline, stop and say so.
