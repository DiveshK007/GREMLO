# Build brief for Claude Code: Gremlo 1.0, round 2

Paste this into Claude Code at the repo root together with the rest of this folder. Read `GREMLO_1.0_ROUND2.md` first; it is the contract. The canvas page "1.0 · round 2" is the visual reference.

## Ground rules
- **Never fake.** Every number on the design boards is seeded. Ship none of them. Unknown values show "—".
- **Art and names.** Only the eight original species go in the public repo. Third-party demo pets stay in a gitignored `assets/demo-pets/`.
- **Money.** The model never authorises money; the deterministic budget check does.
- **No chain names** anywhere in user-facing copy.
- **Each milestone** lands as one PR with tests.

## Milestone 1: assets and the sign (do first)
1. Replace `assets/pets/*` with this folder's packs. The sheets are now 29 rows (1536 × 6032).
2. Update the pet loader to read `gremlo.rows`, `plateAnchor`, `signKit` and `anchors` from `pet.json`. Keep a fallback for v3, 15-row packs: missing rows fall back as in spec §13.
3. Respect anchors when drawing: `edgepeek` is left-anchored, `thrown` is centred, `peek` is top-anchored, everything else sits on the feet.
4. **Mac:** add a `SignPlateView`, an NSView that draws a nine-slice `NSImage` from `signkit.png` with nearest-neighbour scaling and an integer kit pixel equal to `max(3, round(7 × scale))`. Set the text in Inter 600 at 3.7 kit px. Position its bottom-centre at `plateAnchor[frame] × scale`. It never flips with the sprite and carries the AD tab. Delete the old text overlay.
5. **Web:** use `.held`, `.pet` and `.sign` from `tokens.css` on the website hero and the brand console preview.
6. Tests:
   - A snapshot test of the plate at 1× and 2× for all 8 species.
   - Unit tests for the loader's v3/v4 handling.

## Milestone 2: pets alive (Mac)
1. **Idle scheduler** (spec §3): a pure function `nextMicro(state, rng) -> Behaviour?` with injected time. Unit-test the weights, the quiet rules and the day seed.
2. **Gaze:** the cursor-offset-to-frame function with hysteresis. Unit-test the boundaries.
3. **Sit and perch:** `CGWindowList` gives title-bar rects. The pet follows its window's frame changes.
4. **Edge peek:** after a hide ends.
5. **Physics** (spec §4): a small integrator on a display-link timer that runs only while a pet is airborne. Tests:
   - Restitution and the bounce cap.
   - The dizzy threshold.
   - The door locks while a pet is held.
   - The earner pauses impressions while held.
   - With Reduce Motion on, nothing flies.
6. **Social** (spec §5): pair detection, cooldowns and the roll, with an injected RNG.
7. **Context** (spec §6):
   - IOKit power source notifications, `NWPathMonitor`, the clock.
   - The tool-prop matcher as a pure function, with a table test using the tool names from the spec.

## Milestone 3: light mode and sound
1. Theme setting System · Light · Dark. Apply it to the menu bar popover, settings, onboarding and the website. Notch Live stays black.
2. Audit every accent-coloured text in light mode: it must use `accent-on-paper`. Add a contrast unit test (≥ 4.5:1) across all 8 species.
3. **Sound:**
   - Add `assets/sounds/`.
   - Four levels, default "Approvals only".
   - Keep a silence gate (screen share, meetings, Focus, full-screen video) and test it.
   - Rate-limit voice blips to one per 20 s, and only alongside a model bubble with a request ID.
   - The line never plays a sound.

## Milestone 4: Notch Live cost and queue
1. **Usage readers:**
   - Claude Code: parse token usage from the transcript at `transcript_path`, incrementally, tailing the file.
   - Codex: its usage events.
   - Cursor: returns `nil` and the UI shows "—".
   - A bundled price table with an "est" label.
2. **Soft alerts:** per run and per day. They never block or kill an agent.
3. **Approval queue:**
   - A model shared by Notch Live, the menu bar and the phone.
   - Oldest first. Keys ⌥↩, ⌥↓ and ⌥⌫.
   - Risky commands get no shortcut: classify delete, push and spend with a local rule list.
   - Detect answers given in the terminal and grey out the row.

## Milestone 5: CLI, Shortcuts, Raycast
1. A `gremlo` CLI in Swift (or in the Rust core). JSON-RPC over the Unix socket. Commands as in spec §10.
2. **Guards:** no command touches money or approves risky commands. `say` is limited to 80 characters and one call per 10 s.
3. User bubbles are outlined and tagged "you"; model bubbles are filled and keep their request ID.
4. App Intents for Shortcuts. A Raycast extension in its own repo folder.
5. The `gremlo://` URL scheme.

## Milestone 6: focus and team mode
1. **Focus** (spec §12): the timer ring in Notch Live, lines off with the menu bar saying so, the end card. No streak storage.
2. **Team mode** (spec §11):
   - The open-source relay: a tiny HTTP and WebSocket service with a 24 h TTL. Payload limited to team id, sender handle, species, PR number and URL.
   - Event sources: the `gh` CLI hook and an optional GitHub webhook.
   - The visit is always a companion. Rate limits as in the spec.

## Milestone 7: creators and the gallery
1. `gremlo new | validate | preview | submit`. The validator rules are in spec §13; run them in CI on the pets repo.
2. **Codex import** via drag and drop on the menu bar. Imports are local companions only.
3. **Web gallery:** credit for the creator, an install button, and a report button. Nothing is for sale.

## Milestone 8: brands and trust (web and server)
1. **Console A/B:**
   - Up to 4 lines.
   - Even split until 2,000 sightings, then hourly Thompson sampling on opens per sighting, with a 5% floor.
2. **Moment tags** on lines. The matcher runs on the Mac. Reporting enforces k ≥ 50 per moment bucket.
3. **Brand safety:**
   - Domain verification.
   - A line review queue.
   - Closed categories enforced at submit time.
   - Report thresholds that auto-pause a line.
   - Owner block lists.
4. **Signed hourly batches:**
   - Device key in the Keychain; ed25519 over a canonical JSON with a `prev` hash.
   - The server verifies, rate-limits and appends to a public per-campaign log.
   - `gremlo verify <campaign>`.
5. Split the repos and license them MIT: `gremlo-hook`, `-matcher`, `-budget`, `-relay`, `-pets`. Set up reproducible builds and show the hash in Settings → About.
6. **Money page:** the fee shows "—" until it is set. Unspent budget is refunded when a campaign ends.

## Milestone 9: Windows and Linux (after the Mac ships)
1. Extract the Rust core: hooks, matcher, budget, receipts, sprite timing.
2. **Windows shell:** a layered click-through window per display, the taskbar burrow, tray, and WinRT capture detection.
3. **Linux shell:** GTK with layer-shell, falling back to a small always-on-top window.
4. Pets on any platform without reliable screen-share detection never hold lines.

## Definition of done for each milestone
- Tests pass, including the new unit tests listed above.
- No seeded numbers in production code paths.
- Reduce Motion and VoiceOver are checked by hand. Note how you checked them in the PR.
- Screenshots in the PR next to the matching canvas board.
