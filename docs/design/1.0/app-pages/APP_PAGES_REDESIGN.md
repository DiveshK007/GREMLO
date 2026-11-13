# Gremlo 1.0 · app pages redesign

Answers `REDESIGN_BRIEF.md` (2026-11-13). Every page outside `/` now uses the home page's tokens, type, pets and components, in both themes, on desktop and phone.

- **Prototype:** `web/`. Serve the folder and open `index.html`. Each page has a **● STATE** button (bottom right, design review only) that walks every state the brief lists. `?state=<id>&theme=light|dark` deep-links a state.
- **Screens:** `screens/<page>/<state>__<variant>.jpg`. Every state is shot at desktop-dark (1440) and mobile-light (390). Each page's first state is also shot at desktop-light and mobile-dark. `screens/card/*.png` are the 1200×630 share images. `screens/_shell/` shows the phone menu.
- **Shared code:** `web/app.css` (tokens, themes, components) and `web/app.js` (bar, footer, theme switch, the notch, the canvas `Pet` renderer, plates). Page files only hold page markup.
- The product name is **Gremlo** everywhere. The bean species is `gremlo` (accent `#FF5A3C`).

---

## 1. Shared decisions

### 1.1 Theme (open question 1)
- **Default: follow System on every page**, the same as `/`. There is one key, `gremlo.theme` (`system | light | dark`), shared with the home page.
- **No flash:** a 1-line inline script in `<head>` sets `html[data-theme]` before first paint. It's in every prototype page. In Next it goes in the root layout as `<script dangerouslySetInnerHTML>`, before any CSS-dependent paint.
- **Dark:** page `--bg` Ink. Tiles, forms, tables and panels sit on Carbon (`--surface`). Raised things inside a tile use Graphite (`--surface-2`).
- **Light:** page Paper. Tiles and panels on Bone. Inputs sit on a near-white `--field` (`#FFFDF8`), so they read as editable against Bone.
- **Fixed in both themes:** the notch and Notch Live (`#000`), the terminal/code block (`.term`), the QR card (white), pets and sign kits. The certificate is a paper card in Dark and a near-white card with a softer shadow in Light.
- **The switch** sits in the bar on desktop (`SYSTEM` / `LIGHT` / `DARK` mono label with an icon; it cycles). On phones it's a segmented control inside the menu sheet.

### 1.2 Accent text in Light (open question 5b)
- New token **`--accent-text`**. In Dark it equals `--accent`. In Light it equals that pet's **paper-safe** shade.
- Accent **fills** (solid buttons, meters, dots, picked borders) keep the bright accent in both themes. Text on them is always Ink.
- Accent **text** (eyebrows, step numbers, flow labels, stamps, focus rings) uses `--accent-text`.
- Implementation note: custom properties resolve where they're declared. So `--accent-text` is declared on `body, [data-pet]`, not on `:root`. That way it follows a per-section `data-pet`. **Port this to `site.css` too.** It fixes `.eyebrow`, `.steps li span` and `.flow i` on the home page in Light.

### 1.3 Radius (open question 5a): the built site wins
| Token | Value | Used for |
|---|---|---|
| `--r-pill` | 999px | buttons, chips, pills |
| `--r-field` | 10px | inputs, segmented buttons, banners |
| `--r-tile` | 16px | tiles, panels, stages, cards |
| `--r-block` | 0 | full-bleed bands (parade) |

The spec's `--r-control: 6px` and `--r-surface: 14px` are retired. `tokens.css` in this export is the new source; it replaces `docs/design/1.0/tokens.css`. The old app `apps/web/app/tokens.css` ("Gremlo v2") is deleted once the pages move over.

### 1.4 The shared bar
```
(•) Gremlo        [ notch ]        Your pet  Fund a campaign  Park  Money  ◐ SYSTEM  (Get your pet)
```
- **Nav set:** Your pet · Fund a campaign · Park · Money, plus the solid pill CTA **Get your pet**. Gallery, Live numbers and Home live in the footer and in the phone menu.
- **Current page:** the link turns `--fg`, semibold, with a 5px accent dot under it, plus `aria-current="page"`. On `/pet` the CTA carries `aria-current`.
- **Phone (under 860px):** logo · notch (scaled 0.82 under 560px) · **Menu** button. The menu is a full-height sheet under the bar. It has the five main links in display type (current one with a dot), small links for Gallery, Live numbers and Home, then the theme control. Esc closes it.
- **`/pair`:** minimal bar with logo, notch and theme only, no nav. Its footer says the tab can be closed when done.
- **Home page:** replace its in-page anchor nav with this same bar. Home anchors (`#live`, `#hatch`…) become a secondary "On this page" row inside the home hero if you still want them.

### 1.5 The notch off the home page (open question 2)
It stays **live, but only reflects the page's own work**:

| State | When | Content |
|---|---|---|
| rest | default | nothing |
| peek | hover | eyes + pulse |
| think | any request in flight (load, write hooks, check, settle) | breathing accent edge + dots |
| wait | the user must act elsewhere: wallet signature, World App scan | eyes + short mono text ("confirm in your wallet") + pulse |
| done | success, for 2.4 s, then back to rest | eyes + text + ✓ ("campaign #3 is live") |
| egg | `/pet` registering | wobbling egg + "moving in" |
| door | `/pet` done, `/pair` done | the door glow |
| sleep | reserved | |

It is `role="status"` with `aria-live="polite"`, so the text is announced. **It never shows a sponsored line and never shows anyone's data.**

### 1.6 Footer
"**Gremlo** · a pet for every agent" / "All eight species are original. Seeded and example figures are labelled where they appear." Links: Home · Get your pet · Your pet · Fund a campaign · Park · Gallery · Money · Live numbers.

### 1.7 Motion
- No Lenis or GSAP on app pages. They're forms and tables, so native scroll and anchors behave better.
- Allowed: CSS transitions from the motion tokens, sprite animation, count-ups.
- Reduced motion: sprites hold frame 0, count-ups and the parade stop, and every transition is off.

### 1.8 Components added to the 1.0 set
| Class | What |
|---|---|
| `.panel` | Carbon/Bone surface, radius 16 |
| `.stage` | Pet art box with an accent glow from below; `.mini-notch` hangs a notch at its top |
| `.steps` | Pill step strip (`aria-current="step"`, `.done`) |
| `.meter` | Budget meter, `role="meter"`, `.hot` at ≥80% |
| `.tbl` | Table that **stacks into labelled rows under 760px** (uses `td[data-th]`), never scrolls sideways |
| `.bad` | Error: fg text with a Signal square, always `role="alert"` (replaces the unstyled `.error`) |
| `.note` | Status line, `role="status"` |
| `.seeded` | Striped dashed banner for seeded data |
| `.ex` | Small outlined "example" tag |
| `.pill` | Status pill (live pulses, `.warn`, `.off`) |
| `.hash` | Mono receipt link, wraps with `break-all`, always visible, ↗ marker |
| `.qr` | White card with a quiet zone, both themes |
| `.toast` | Bottom toast for "Link copied" |
| `.check` | Accessible custom checkbox |

---

## 2. Bugs from A7, fixed in the design
- **Nested `<main>`:** the layout owns the only `<main>`. Pages render sections.
- **`.error`** is gone. Every error uses `.bad` with `role="alert"`.
- **`/money` status:** check `res.ok`. A non-2xx shows the server's message in `.bad`, not dashes.
- **Pet name rule:** one rule everywhere, `^[a-z0-9-]{2,24}$`, lowercased as you type with a mono echo. The home certificate's 14-character any-case rule changes to this. The card scales the name down past 14 characters.
- **Park tile:** the tile is a `<button>` only. The visit link lives in a separate "picked pet" panel, so there's no link inside a button.

## 3. Copy changes (no chain names in product copy)
| Where | Before | After |
|---|---|---|
| `/me` proof line | "Earnings come from settlements in the vault, paid to …" | "Earnings come from settlements, paid to …" |
| `/me` compute | "…charged a fixed per-tier rate in NEAR, not the real USD bill from NEAR AI, with the call's completion id in the onchain log." | "Each thought is charged a fixed rate per tier, not the provider's real bill, and every charge has a receipt and the call's completion ID below." |
| `/me` unknowns | "unknown", "chain unreachable" | `—` plus one line: "Can't read the payout record right now." |
| `/me` budget error | "Can't read the vault right now." | "Can't read the pet's budget right now." |
| `/live` hero | "Live on NEAR testnet" | "Live now" pill. The network is named only in the "Proof · technical" footnote |
| `/live` totals | "Views settled onchain", "Live from the chain" | "Views settled", "Read from the campaign contract's own totals." |
| `/live` TryHook | "Writing on NEAR AI Cloud…" | "Writing with private inference… Real inference, usually 20 to 60 seconds." |
| `/me/card` | "Earned from sponsored hooks…" | "Earned from sponsored lines while a coding agent worked." |
| `/me/card` level | "?" | `—` |

Kept technical on purpose:
- `/brand` amounts in NEAR, the contract link, "Paid onchain, but…"
- `/pair` (NEP-413, Secure Enclave, the account).
- Account IDs anywhere.

---

## 4. Pages

### 4.1 `/pet` · Get your pet (13 states)
- **Layout:**
  - Head: "One human. One pet." with the lead.
  - Left: a panel with the step strip, wallet row, name (big input, mono echo, rule hint) and payout field, then the solid **Prove you're a real person** button.
  - Right: a stage with a mini notch and the **egg**. "Your egg hatches on your Mac the first time your agent works. You find out the species then." That turns "the web doesn't know the species" into the hatch surprise.
- **Scan:** a white-quiet-zone QR, **Copy link**, a "Waiting for your phone…" status and the code expiry. Staging gets a **Test mode** pill and the simulator copy. The notch goes to `wait` with "waiting for your phone".
- **Registering:** the egg wobbles and cracks. The status is the brief's line. No step is highlighted. The notch shows `egg`.
- **Done:** a certificate with Owner, Moved in, "Species: hatches on your Mac" and "First agent: —", stamped "one human · one pet". Next to it: "mochi is moving into your notch." Under that, **Registered** and **Marked verified** tx links (or "Registered." alone), then **See your pet**. The notch shows `door`.
- **Denied:** clearly not an error. It uses an accent-outlined panel and a huge outlined "1" with the pet sitting beside it. Eyebrow "One human, one pet", the brief's copy, then **Back** and "See your pet →".
- **Name taken (new, R4 §18):**
  - The field turns invalid with "mochi is taken."
  - Chips offer **mochi-2** and **mochi-3**: the next free numeric suffixes, checked with `GET /pets/:name` returning 404.
  - Then "or pick another name. Names are free, never auctioned."
  - Replace the raw "pet already registered" with this.
- **Errors:** a human headline over the raw server message in mono, "Your details are kept. Nothing was registered and nothing was charged.", then **Try again**.

### 4.2 `/me` · Your pet (13 states)
- **Header:** a slim lookup row, then the pet's name as a giant display word.
  - Eyebrow: "Your pet · Pip · Buddy".
  - Mood pill + reason.
  - **Share this week on X** (ghost), plus "See the share card →".
- **Stage:** the real species sprite, with the page accent from the species (`body[data-pet]`). Money shapes it:
  - Thriving: celebrate row, bouncy.
  - Stable: idle.
  - Hungry: idle at 2 fps, smaller and faded.
  - Asleep: the pet stays inside a sleeping notch with "Too hungry to leave the notch."
- **Growth:** `.grow` (Egg, Hatchling 0–9, Buddy 10–49, Elder 50+). The current stage is lifted and shows its meal count.
- **Numbers:** six tiles (2 columns on phones): This week, Paid by brands all time, Level, Streak, Views today, Mood. Unknowns show `—` with a reason. Then the proof line with the payout link.
- **Meals (compute budget):** a big "Budget left, against the daily cap" figure with a `role="meter"`. It turns Signal under 20%. Tiles: Spent on thinking all time, Charged today of cap, Rate per call.
- **Proof · last thoughts:** When, Action, Model, Completion id, Charge (tx link or "– not charged"). Rows stack under 760px. Completion IDs and charge links are always visible.
- **Other states:**
  - First visit: "How is your pet doing?" with the lookup and a peeking pet.
  - Loading: dashes plus the notch in `think`.
  - 404: "No pet called “mochii”." with a spelling hint.
  - Server down: a plain-words message and **Try again**.
  - Seeded: the banner above the header.
  - Nulls: dashes with reasons, and the budget panel becomes a `.bad` panel.
  - No thoughts: an empty panel.
  - Species unknown: Gremlo sprite and accent, with "Species not known yet".

### 4.3 `/me/card` (8 variants)
- 1200×630, **dark only.** Social cards can't know the viewer's theme, and the dark desk matches `/`.
- **Left:** logo dot in the species accent; seeded tag when seeded; "PIP · BUDDY" in the accent; the name (168px, 92px past 14 characters); This week / Level / Streak; then "Earned from sponsored lines while a coding agent worked."
- **Right:** a Carbon panel with the accent glow, a mini notch and the species' celebrate still.
- **next/og:** use `og/card.tsx`. Flex and inline styles only. Load Bricolage, Inter and JetBrains Mono into the route. Use **pre-cut stills** from `assets/stills/<species>-celebrate.png` (384×416), because Satori can't crop a sprite sheet.
- Every font-family needs a generic fallback in the list (`'Bricolage Grotesque', Inter, sans-serif`). Without one, Chromium rendered the inline family as Times in testing. Satori is stricter still.
- 400 for a missing `?pet`, 404 for an unknown pet, unchanged.

### 4.4 `/brand` · Fund a campaign (30 states, open question 4)
- **Two tabs:** **New campaign** and **Campaign dashboard**. `/brand?c=<id>` opens straight on the dashboard, which works on its own.
- **New campaign:**
  - Wallet strip, then a two-column layout.
  - **Left column:**
    - **01 Your product:** the brief fields with limits; proof points with the "returns or profit" rule; CTA and Link; the required claims checkbox; **Write my hooks** / **Write new hooks**.
    - **02 Pick 1 to 4 hooks:**
      - Counter, the traffic line, a format filter (`.seg`), and grouped line toggles (`aria-pressed`). Each shows "written by AI · <request id>" or "written by you", plus `n/40`. Unpicked lines disable at 4.
      - The moment picker per picked line, with the "nothing about their work is sent" line.
      - A collapsible "n hooks didn't pass the claim checks" list.
      - Write your own, with a counter that uses `.count.over`.
    - **03 Budget:** NEAR-suffixed fields, the live "Ends…" hint, and the optional email.
  - **Right column, sticky summary:**
    - The preview plate (`.held` + `.sign` with the species kit and the `AD` tab). Screen readers hear "Sponsored, Clearlog: <line>". It never truncates.
    - Lines/budget/price/runs and the big estimated views.
    - The **one accent button, Fund campaign.** Its label steps through Checking your hooks… → Confirm in your wallet… → Saving your hooks….
    - Hints, errors and the contract link.
  - **Phones:** the summary drops below and a sticky bottom bar shows "2 lines · ~100 views · 0.1 NEAR [Review & fund]".
- **Writing:** a panel with the Byte tools animation, "Writing 16 hooks…" and a seconds counter (`role="status"`). The notch shows `think`.
- **Receipt:**
  - The `.end` layout: "Campaign #3 · live" pill, "Your campaign is live.", a big stage with the rotating plate preview, then tiles for Budget / Price per view / Estimated views ("an estimate, not a promise") / Ends / Receipt tx.
  - Actions: **View dashboard**, **Copy share link** (becomes "Link copied" for 2 s), **Start another**.
  - **Funded, not saved:** an alert banner with the brief's exact sentence, "Paid. Hooks not saved yet.", the tiles with the receipt, then **Copy receipt** and **Contact us**.
- **Dashboard:**
  - Campaign ID lookup with **Check** and **Settle views**; "Campaign #3" heading with a status pill and share link.
  - Budget panel: the "Budget · spent · left" line, a meter (Signal at ≥80%), the 50% and 100% messages with "Top up below…", Top up with the tx result, the status line, **Close and refund** once the window has passed, and the refund tx.
  - Settlement result panel: none queued / paid with a tx per pet / seeded tag / stopped with an error.
  - **How each line is doing:** the table shows the **hook number and the line text**, with a "best so far" tag. It needs the server to return line text with stats (see §5).
  - Facts list: fraud check, voided, waiting, by moment, paused by reports, email.
  - Right column: **Proof** (signed reports, public log link, `gremlo verify 3` in a terminal block, the Arkiv mirror line) and a live preview plate.
  - Stats-unavailable state: a `.bad` panel saying the budget figures come straight from the contract.

### 4.5 `/park` (7 states)
- The home page yard (sky, grass, trees; stars in Dark; a daylight palette in Light), with **real** walkers as `<button>`s and name tags (name · species · stage).
- Up to 12 walkers on desktop and 5 on phones. Everyone is also listed below in **Everyone out now** (accessible tiles; "n pets · shuffled on every visit").
- **Tap a pet:** it plays a learned trick (backflip 35 with the jump arc, juggle 36, moonwalk 37), or the greet row if it knows none. A **picked panel** appears with the name, species · stage, outfit, **Send my pet to visit** (`gremlo://visit?to=<id>`) and "Opens the Gremlo app on your Mac. Without the app installed, nothing happens: get your pet first."
- **Rules row:** Pets only · No ranking · Tricks are earned · **Never an ad**. Then the join line. The "samples" line is removed.
- **States:** loading ("Opening the gates…" plus tile skeletons), empty ("Nobody is out right now." with a bench), error (dimmed yard, `.bad`, Try again).

### 4.6 `/gallery` (8 states)
- **Species cards:** a stage with the reviewed sheet animating, the name in display type, "by <creator>", rows · listed date · id, then **Install** (`gremlo://install?species=<id>`, with the CLI shown in a toast) and **Report**. No prices, no "buy".
- **Paused (decision: show it):** greyscale art, a "Paused · being re-checked" pill, Install disabled, "New hatches paused after 3 reports." Hiding it makes a species vanish without explanation for people who already have it.
- **Report:** a dialog with four reasons (not the creator's own art / offensive or unsafe / broken sprite / something else), the 3-reports rule, then **Send report** → "Thanks, report sent." The reporter is never named on the card.
- **Make one:** the four CLI commands in a terminal block, a numbered explanation, and "Only art you made…".
- **Empty:** "None listed yet." with a hatching egg and a link to how to make one.

### 4.7 `/money` (4 states)
- The home Money section: "It holds one line. That buys its lunch.", then the parade of plates labelled "example lines".
- **Six step tiles** (3×2). Step 02 shows a big `—` until the fee is published.
- **So far:** five big counters (Settled sightings, Campaigns, Pets paid, Paid to pets, Paid for thinking) that count up, respecting reduced motion. Dashes while loading; `.bad` plus dashes on error; the seeded banner when seeded.
- **The rule:** a checklist of the sighting conditions, plus `gremlo verify <campaign>` in a terminal block. A link to a campaign's public log appears **only when a real campaign exists** (from `/campaigns/active`).
- Wording to settle in code, not design:
  - Add "weekly" to step 5 only if the payout job is actually weekly.
  - Add "no repeat brand" to the rule only if the server enforces it.
  - The copy must match what runs.

### 4.8 `/pair` (8 states)
- Minimal bar. The art is a laptop with a black notch and the pet on screen, plus a "Secure Enclave key" chip.
- Pet and Device tiles (the device is mono, "first 16 hex of SHA-256 over this Mac's key").
- A big **✓ No transaction, no fee** chip, the brief's explanation, and a disclosure with **the exact message you'll sign** (byte-exact, plus the recipient and nonce note).
- **Approve pairing** → "Approve in your wallet…", with the notch in `wait` showing "sign in your wallet".
- **Done:** a celebrating pet, "This Mac is paired.", both lines from the brief, then "✓ You can close this tab." in the same chip style.
- Errors: bad link, unknown pet (links to Get your pet), wrong account (403), other.

### 4.9 `/live` (8 states)
- Trimmed to proof: "The real numbers, right now."
- A big stage with the live plate (rotating) and a **Live now** pill, or the **Example hooks** tag with "No campaign is running. These are examples."
- Four totals (`…` while loading, `—` when unreachable plus `.bad`).
- **TryHook:** the product field (min 3 characters) and **Write hooks**. Writing status. The result shows three pets holding the three lines, captioned "Example only · written by AI · request <id>", plus a format/text list. Errors for too short and rate limited.
- A **Proof · technical** footnote is the only place that names the network, the contract and the inference provider.
- Dropped as duplicates of `/`: hero, how-it-works, split, demo video, Signal band.

---

## 5. API asks (the design needs these)
| Endpoint | Add | Why |
|---|---|---|
| `GET /pets/:name` | `species`, `stage`, `meals` | Species sprite and accent on `/me`, `/me/card` and `/pet` done; the growth stage |
| `GET /pets/:name` 404 | (exists) | Name-taken suggestions on `/pet` |
| `GET /park` | `tricks: string[]` | Tap → a trick it actually learned (R4 §14). Update the R4 §20 park payload test to `{id, name, species, stage, outfit, tricks}` |
| `GET /gallery` | `paused: boolean`; `GET /gallery/:id/sheet.webp` | Show paused species; card art |
| campaign stats | line text per hook | The dashboard table shows the line, not just "#1" |

## 6. Open notes for you
- **Streak on `/me` and the card.** The 1.0 rules say no streaks. The current page has one and the brief asks to keep its content, so it's designed in and marked "just for fun". **Recommend** replacing it with a count that never resets (e.g. "Days with a meal: 31"). It's your call.
- `gremlo://` deep links do nothing without the app. Every place that uses one says so in text.
