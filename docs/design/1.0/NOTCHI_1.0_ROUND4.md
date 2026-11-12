# Notchi 1.0, round 4: alive, useful, social, everywhere

Extends `NOTCHI_1.0_ROUND3.md`. Where they disagree, this file wins.
The canvas page **1.0 · round 4** is the visual reference (six boards: Bug hunt, Git moods, Dreams/tricks/seasons, The room, Show it off, Wherever you look). The website prototype in `web/` has the bug hunt, the room, dreams and the pet park working.

Skipped on purpose, do not add: leaderboards, weather, loot boxes, paid colour packs, streaks, any brand placement beyond the plate.

---

## 1. Packs v6: 39 rows, plus a props sheet

Sheets are 1536 × 8112 (39 rows of 192 × 208). Rows 0–30 are unchanged. `ext3.png` holds rows 31–38 alone if you want to lazy-load them.

| Row | Name | Frames | Use |
|---|---|---|---|
| 31 | chase | 6 | running after a bug; frame 4 is the pounce |
| 32 | gulp | 6 | pounce, chomp, chew, chew, swallow, heart |
| 33 | covereyes | 4 | `push --force`: paws over eyes, one peek, back |
| 34 | tangled | 4 | merge conflict: wrapped in yarn |
| 35 | backflip | 6 | trick. Frames 1–4 are a tucked spin in place; **the app adds the jump arc**: 0.5 s, peak 1.6× body height (`pet.json → arcs`) |
| 36 | juggle | 4 | trick. Loop it 2–3 times |
| 37 | moonwalk | 4 | trick and release tag. Wears shades. Slide the pet backwards while it faces forwards |
| 38 | wrist | 4 | meeting heads-up: checks a watch, taps it |

Accessories hide on rows 33, 34, 35 and 37 (`headAnchor` is null there; moonwalk brings its own shades).

**`assets/props/props.png`** is 256 × 128 at 1 px per sprite unit; `props.json` has every rect. Draw at the pet's unit size (7 px per unit at full size), feet-aligned.

| Group | Items |
|---|---|
| Bug | `bug0`–`bug3` (crawl, 4 frames, 32 units apart), `bugsquash` |
| Toys | `yarn` |
| Dream icons | `d-wrench` `d-flask` `d-bug` `d-star` `d-moon` `d-heart` `d-check` `d-merge` |
| Seasonal | `s-diya` `s-snow` `s-pumpkin` `s-lantern` |
| Furniture | `f-rug` `f-lamp` `f-plant` `f-shelf` `f-beanbag` `f-poster` `f-fishbowl` `f-lights` `f-records` (show it as **Radio** in the UI) |
| Guestbook | `paw` |

Regenerate with `python3 tools/roster4.py` (writes `packs4/`; imports roster3 → roster2 → roster).

---

## 2. Bug hunt

**Detecting a test run.** On `PostToolUse` for Bash, match the command against a runner list: `npm|pnpm|yarn|bun test`, `vitest`, `jest`, `pytest`, `go test`, `cargo test`, `forge test`, `mix test`, `rspec`, `dotnet test`, `swift test`. Users can add patterns. Failure = non-zero exit. Pass = zero exit for the same runner in the same session.

| Event | What happens |
|---|---|
| Failing run | One bug crawls out along the bottom screen edge. Max 3 on screen. Bugs never walk over windows, only the bottom edge or the Dock top. |
| Companions | Chase (row 31), but never catch until a pass. The earner only watches, eyes following (gaze row). |
| Passing run | The nearest pet catches each bug in turn: pounce (row 31 frame 4) → gulp (row 32). +1 in the bug jar per bug. |
| User clicks a bug | Squash (`bugsquash`, fades in 1 s). The pet sulks (fail row) for a beat. Squashed bugs don't count in the jar. |
| Screen share, or session ends | All bugs leave. |

The **bug jar** lives in the room. It is a count, not a streak: nothing resets, nothing is lost.

## 3. Stuck detector

| | |
|---|---|
| Triggers | The same tool fails with the same normalised error 5 times in 10 minutes, or the same file is edited and reverted 3 times. |
| Normalising | Strip numbers, hex, paths, timestamps; compare the first line plus the error class. All on the Mac. |
| Notch | "Going in circles · same error 5× · 7 min", the error line, and three buttons: **Ignore this run**, **Copy a nudge**, **Show me**. |
| Copy a nudge | Puts on the clipboard: "You've hit this error 5 times. Explain the cause before trying again." The user pastes it. |
| Show me | Brings the agent's terminal or editor window to the front. |
| Never | Stops, interrupts or messages the agent by itself. |
| Pet | Raises its flag (row 7), worried look. Sound only if sounds are on. |

## 4. Git moods

`notchi hook install git` adds hooks to the current repo (or `--global` via `core.hooksPath`, chaining any existing hooks). `notchi hook remove git` undoes it. Each hook sends one line to the app's local socket: `{"type":"git","event":"<name>","repo":"<hash of path>"}`. No messages, no diffs, no file names.

| Event | Detected by | Animation |
|---|---|---|
| commit | `post-commit` | greet row (3), once |
| PR merged | GitHub, only if the user connects it | celebrate row (4) plus fireworks from the notch |
| force push | `pre-push`: remote sha is not an ancestor of the local sha | covereyes (33) |
| merge conflict | the app watches `.git/MERGE_HEAD` and unmerged index entries | tangled (34) until `MERGE_HEAD` is gone, then a shake-free |
| release tag | `reference-transaction` hook sees `refs/tags/v*` created | moonwalk (37) along the bottom edge |

## 5. Drop zone

The notch window is an `NSDraggingDestination`. While something is dragged over it, the notch opens one size and glows.

| Dropped | Clipboard gets |
|---|---|
| Files | Their paths, one per line, quoted if they contain spaces |
| An image | The path **and** the image (`NSPasteboard` image type), so agents that accept pasted images get it |
| Text | The text as is |

A toast says "Ready to paste". Nothing is uploaded, nothing is typed into the agent.

## 6. Session scrubber

Hover the notch after a run ends: a strip of bars, one per hook event, coloured read / edit / run / failed / approval / passed. Drag to scrub; the label shows time, tool and argument summary. Click a bar to copy that step's command or open the file it touched. Data: tool name, start, end, exit status, argument summary. Kept on the Mac for 7 days.

## 7. Dreams

In the sleep state, a bubble rises from the notch and shows one icon per 1.7 s: that day's events in order (edits → wrench, test runs → flask, failures → bug, merges → merge, passes → check, celebrations → star, thanks/approvals → heart, last → moon). Hover: "Mochi is dreaming about 23 edits and one stubborn test." Counts by default; a model-written line only if the user turned that on.

## 8. Tricks

| Trick | Learned when | Row |
|---|---|---|
| Backflip | 25 approvals answered | 35 |
| Juggle | a session with 100 tool calls | 36 |
| Moonwalk | the first release tag | 37 |

Do it from the menu bar (Tricks) or `notchi trick backflip`. Once learned, the pet may show off on its own, at most once an hour while idle. Earned, never sold.

## 9. Seasons

Scenery only: nothing to collect, nothing that runs out, nothing for sale. Region-aware from the system calendar and locale; off in one click.

| Season | Scenery |
|---|---|
| Diwali | diyas along the bottom edge, a lantern hangs from the notch |
| Winter | snowflakes, never more than 6 at once |
| October | a pumpkin the pet sits next to |

## 10. Meeting heads-up

EventKit, only with permission; titles never leave the Mac. Five minutes before an event: the pet checks its watch (row 38), the notch shows "standup in 5" and a countdown. At start it waves and goes home until the meeting ends. If an agent still needs approvals during the meeting, they go to the phone.

---

## 11. The room

Pull the notch down. Furniture costs the same earned stars as the Closet (one ledger). Each piece has a fixed spot so the room always looks tidy. Clicking a placed piece puts it away; you keep it.

| Item | ★ | Spot (units, room 180 × 104) | Pet uses it |
|---|---|---|---|
| Fairy lights | 9 | 74, 6 | |
| Poster | 5 | 120, 20 | |
| Shelf | 12 | 18, 26 | |
| Rug | 8 | 77, 90 | stands on it |
| Lamp | 10 | 36, 76 | |
| Radio | 10 | 52, 81 | bops (celebrate row) while an agent works |
| Beanbag | 14 | 112, 84 | naps on it (night row) |
| Fishbowl | 15 | 136, 82 | watches the fish (gaze, frame 4) |
| Plant | 6 | 158, 79 | |

The room is never shown with a sponsor in it.

## 12. Guestbook

The owner shares a visit link (or taps a pet in the park). If the host allows visits, the visitor's pet walks into the room, looks around for 20 s, sits on the rug if there is one, and leaves a paw print. The guestbook keeps: visitor pet name, species, stage, outfit, time. No messages, no owner names. Visits off in one click.

## 13. Stream mode

A local HTTP server on `127.0.0.1` serves `/overlay` (transparent page) and `/events` (SSE). OBS adds it as a browser source.

- Shows: the pet, its mood, tool count. Approvals read "waiting on me", never the command.
- **Never a sponsored line.** Sightings assume one person is looking; a stream would count wrong. Turning stream mode on switches the plate off.
- The duck-on-screen-share rule is suspended while stream mode is on, because the user chose to show the pet.

## 14. Pet park

A public page, opt-in, off by default. Each pet publishes only name, species, stage and today's outfit. Random order on every load: no ranking, no counts, no "most active". Tap a pet: it does a trick it has learned, and offers a visit. Leaving removes the pet at the next refresh. The service stores exactly those four fields plus a random pet id.

## 15. Weekly postcard

Sunday 18:00 local, rendered on the Mac as a PNG from that week's counts: runs watched, bugs caught, a trick learned, what it wore. The note is a template unless the user allows model-written text. Leaves out code, repo and file names, prompts, earnings and sponsors. Save or copy; nothing is posted.

---

## 16. VS Code and Cursor extension

One extension, published to the VS Code Marketplace and Open VSX (Cursor installs from Open VSX).

- Status bar item: pet face (peek row), name, mood, tool count for the current run. Click opens a **Notchi** panel (webview) where the pet walks along the bottom.
- Talks to the Mac app over the same local socket. If the app isn't running it says "Notchi isn't running" and does nothing else.
- Approvals appear in the editor too; answering anywhere clears the others.
- Never shows the sponsored line. That stays on the plate in the notch.

## 17. Watch complication

WidgetKit complication from the iPhone companion app. Circular: pet face inside a ring that fills as the run goes. A row "2 waiting on you"; tapping opens a list with Allow/Deny for ordinary tool calls. Anything that spends money or touches keys says "Open on the Mac". Haptics: `.notification` on a knock, `.success` on done; silent during a screen share or Do Not Disturb.

## 18. Readable pet accounts (optional)

Under the hood each pet can get a named account, `mochi.notchi.near`, instead of a long key string. **Product copy never names the chain.** The UI says "purse", "earned", "paid for thinking". The account ID appears only in Settings → Advanced.

- `notchi.near` runs a small factory contract. Only the parent account can create sub-accounts, so the factory creates `<pet>.notchi.near` at hatching and deploys a **purse contract** to it.
- The user's own wallet holds the full-access key (withdrawals, closing).
- The Mac app holds only a **function-call key** limited to the purse's `pay_inference` method. Function-call keys can't transfer funds directly, so every spend goes through the purse, which checks per-call and daily caps and an allow-list of inference providers.
- The model can ask for a payment; it can never sign one. Same rule as before.
- Name taken: offer `mochi-2` or let the user pick. No auctions, no paid names.
- Offline or unreachable: spending stops safely, the pet keeps working, it just stops thinking out loud.
- Balances show `—` until connected. Never a made-up number.

---

## 19. Website (`web/notchi.html`)

New in this round:
- Sprites are the 39-row v6 sheets; `props.png` is loaded once.
- **Hero bug hunt:** "Fail a test" drops a bug (max 3), the pet chases; "Make it pass" and it catches and eats them; click a bug to squash it. A bug jar count appears. Hidden under Reduce Motion.
- **The room** section: furniture bought with an example wallet of 40 stars; the pet walks between the beanbag, the fishbowl and the radio. **Dreams** card cycles the day's icons.
- **Pet park** section: 8 sample walkers (4 on phones) with name tags; tap one for backflip / juggle / moonwalk. Labelled as samples.

## 20. Tests to add

- Runner matcher: table test of commands → runner or none.
- Bug lifecycle: fail → bug, 4th fail → still 3, pass → all eaten in order, squash → jar unchanged, screen share → all gone.
- Stuck detector normaliser: errors that differ only in numbers/paths compare equal.
- Git: force-push detection with a fixture repo; MERGE_HEAD watcher.
- Drop zone: files with spaces are quoted; image drops put both types on the pasteboard.
- Stream mode: the plate is off and the sighting counter does not move while it's on.
- Park payload: serialiser outputs exactly `{id, name, species, stage, outfit}`.
- Postcard: rendered text never contains a path, repo name or currency.
- Purse: a function-call key cannot transfer; caps reject the call that crosses them.
