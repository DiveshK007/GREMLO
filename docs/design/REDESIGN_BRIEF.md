# Redesign brief: the web app pages

For Claude Design. Redesign every web page that isn't on the 1.0 design yet, so the whole site looks like `/`.

Written 2026-11-13 from the code on `main`. Copy in quotes is the real text in the code today, so you can keep it or
rewrite it. Each page lists its file, so a developer can check anything here.

**What is already new:** only `/`, the home page (`apps/web/app/(site)/`, ported from `docs/design/1.0/web/gremlo.html`).

**What still has the old look (8 pages + 1 image):**

| Route | Who uses it | File |
|---|---|---|
| `/pet` | developer (new pet owner) | `apps/web/app/(app)/pet/page.tsx` |
| `/me` | pet owner; anyone with a shared link | `apps/web/app/(app)/me/Me.tsx` (+ `page.tsx` for share metadata) |
| `/me/card` | social networks (share image, 1200x630) | `apps/web/app/(app)/me/card/route.tsx` |
| `/brand` | brand | `apps/web/app/(app)/brand/page.tsx` |
| `/park` | visitor, pet owner | `apps/web/app/(app)/park/page.tsx` |
| `/gallery` | visitor, species creator | `apps/web/app/(app)/gallery/page.tsx` |
| `/money` | brand, judge, visitor | `apps/web/app/(app)/money/page.tsx` |
| `/pair` | pet owner (opened from the Mac app) | `apps/web/app/(app)/pair/page.tsx` |
| `/live` | judge, visitor (the old home page) | `apps/web/app/(app)/live/page.tsx` |

All eight pages share one layout (`apps/web/app/(app)/layout.tsx`) and one stylesheet pair (`apps/web/app/tokens.css`,
`apps/web/app/globals.css`). The home page has its own layout and stylesheet (`app/(site)/layout.tsx`, `site.css`)
and doesn't share either with the app pages.

---

## Part A. Shared

### A1. The two looks today

| | Old (app pages) | New (`/`) |
|---|---|---|
| Background | Paper `#F4F2ED`, light only | Ink `#0B0B0B` "dark desk", with a Light mode |
| Theme switch | none | System · Light · Dark button in the bar |
| Header | text logo "Gremlo" left, 5 text links right, scrolls away | fixed 38px menu bar, logo with an accent dot, the live notch in the centre, links and a solid pill CTA on the right |
| Buttons | square (radius 0), ink fill, 48px; `.ghost` = 1px outline | pill (radius 999), accent fill `.btn.solid`, `.btn.ghost` = 1.5px outline, lifts 2px on hover |
| Inputs | underline only, transparent | filled Carbon box, 1.5px rule border, radius 10, 54px tall, accent border on focus |
| Sections | "no cards": rules between blocks | Carbon tiles with radius 16 (`.flow div`), big `.sec-head` with an eyebrow, display title and a side paragraph |
| Accent | Signal `#FF5A3C` only | per-section pet accent (`data-accent`), animated through `@property --accent` |
| Pet art | the Ink sprite (`gremlo-ink.webp`) in CSS | canvas sprites for all 8 species (`class Pet` in `public/site/site.js`), anchors from each `pet.json` |
| Footer | one line: "Testnet build. Thinking runs on private inference; one human, one pet, verified by World." | mono line: "Gremlo · a pet for every agent · Park · Gallery · Money · Live numbers" and "All eight species are original. Figures on this page are examples." |

### A2. Header, nav and footer today

Old header (all app pages):

```
Gremlo                     Get your pet  Your pet  Fund a campaign  Park  Money
```

There's no link to `/gallery`, `/pair` or `/live` in it. The current page isn't marked.

New bar (`/`):

```
(•) Gremlo            [  notch  ]          SYSTEM  Notch Live  Hatching  Pets  Closet  (Hatch yours)
```

Under 760px the bar shows only the theme button and the CTA. Under 560px the nav is hidden and the notch is scaled to 0.82.
Its links are in-page anchors (`#live`, `#hatch`...), so they don't work from other pages.

Footer links today:
- On `/`: Park, Gallery, Money, Live numbers (`/live`).
- On app pages: none.

**To design:** one shared bar and footer for every page. Things to decide:
- The nav set. Probably Get your pet, Your pet, Fund a campaign, Park, Money, with Gallery and Live numbers in the footer.
- What the centre notch does off the home page. The notch component and its states are in `site.css` under "the notch component".
- The current-page state.
- The phone menu.

`/pair` is opened from the Mac app and can keep a minimal header.

### A3. Tokens and fonts in use

Fonts are the same on both looks, from Google Fonts:
- Bricolage Grotesque (opsz 12-96, wdth 75-100, wght 400-800)
- Inter (400, 500, 600)
- JetBrains Mono (400, 500)

Spec (`docs/design/1.0/GREMLO_1.0_DESIGN.md` §1, Type):

```
Display  Bricolage Grotesque 800 · -0.04em · lh .9 · 64-230px
Heading  Inter 600 · -0.02em · 22-34px
Body     Inter 400 · 15-17px · max 62ch
Mono     JetBrains Mono 500 · 10-13px · IDs, hashes, labels only
```

The new home page uses Display with `font-variation-settings: 'wdth' 80, 'opsz' 96` and letter-spacing -0.035em.

The 1.0 token file is `docs/design/1.0/tokens.css`. Its key values:
- **Neutrals:** Ink `#0B0B0B`, Carbon `#141414`, Graphite `#1F1F1F`, Bone `#E9E6DF`, Paper `#F4F2ED`, Notch `#000` (same in both themes).
- **Dark text and rules:** `--text` .85, `--text-2` .62, `--text-3` .45, `--rule` .14, all of Paper on Ink.
- **Light:** `--bg` Paper, `--surface` Bone, text and rules use Ink at the same steps.
- **Accent per pet**, with a paper-safe shade for text on paper:

  | Pet | Accent | Paper-safe |
  |---|---|---|
  | gremlo | `#FF5A3C` | `#C1442D` |
  | pip | `#FFC93C` | `#876A1F` |
  | moss | `#8FD14F` | `#52792D` |
  | gloop | `#2ED3B7` | `#1B7C6B` |
  | byte | `#4CC9FF` | `#2C7696` |
  | puff | `#8FA8FF` | `#5B6BA3` |
  | wisp | `#B48CFF` | `#7C60AF` |
  | tako | `#FF7AB6` | `#AA5179` |

- **Radius:** `--r-block: 0`, `--r-control: 6px`, `--r-surface: 14px`.
- **Motion:** snap 160ms `cubic-bezier(.2,.8,.2,1)`, settle 280ms `cubic-bezier(.3,1,.4,1)`, bloom 420ms `cubic-bezier(.34,1.4,.5,1)`.
- **Space:** `4 8 12 16 24 40 72 120`.
- **Shadow:** only on floating surfaces, with a separate light-mode value.

Where the built site and the spec disagree, decide which one wins and say so:
- **Radius:** the site uses pill buttons (999), inputs at 10 and tiles at 16. The spec says controls 6 and surfaces 14.
- **Light mode:** `site.css` swaps the variable values (`--ink` becomes `#F4F2ED`, `--paper` becomes `#0B0B0B`).
  The site never uses the paper-safe accent shade, so accent-coloured *text* in Light mode fails contrast on paper.
  Examples: `.eyebrow`, `.steps li span` and `.flow i`. The spec (R2 §7) says accent text on paper uses the paper-safe shade.
- **Old app tokens:** they live in `apps/web/app/tokens.css` ("Gremlo v2 — minimalist maximalism": Ink, Paper,
  Signal and derived greys, radius 0, popover 14). They should go away once the pages move over.

### A4. The System · Light · Dark switch

- **What it does today:** it exists only on `/`, as `#themeBtn` in the bar. `public/site/site.js` cycles system → light → dark,
  saves the choice in `localStorage` under `gremlo.theme`, and sets `html[data-theme="light"|"dark"]`. "System" follows
  `prefers-color-scheme`.
- **What the spec says** (R2 §7): "Settings offers System · Light · Dark. The website gets the same switch."
  The notch and Notch Live stay `#000` in both themes, and the pets and sign kits never change.
- **To design:** every page in both themes, with the same switch in the shared bar.
- **Implementation note:** in a client-rendered page, the saved choice has to apply before first paint so there's no flash.

### A5. Components the new home page already has

All of these are in `apps/web/app/(site)/site.css` and the markup in `markup.ts`. Reuse them by name:

| Component | Class / id | Good for |
|---|---|---|
| Menu bar + logo dot | `.bar`, `.logo i` | shared header |
| Notch with states | `.notch[data-state=rest/think/peek/live/knock/done/room/sleep/egg/door/bye]` | header centre; page hero art; status ("waiting for your phone" could be `think`) |
| Section head | `.sec-head` (eyebrow + `.dsp` h2 + side paragraph) | every page title |
| Eyebrow | `.eyebrow` (mono 11px, uppercase, accent) | kickers like "Your pet", "Pair a Mac" |
| Buttons | `.btn.solid`, `.btn.ghost`, `.chipbtn` | all actions |
| Field + segmented control | `.field label/input`, `.seg button[aria-pressed]` | every form; the moment picker; tones |
| Certificate | `.cert` (paper card, dashed inner border, stamp, `.ex` example note) | `/pet` "moved in" screen, `/me` header, `/me/card` |
| Growth stages | `.grow .st` (Egg, Hatchling 0-9 meals, Buddy 10-49, Elder 50+) | `/me` stage |
| Wallet | `.wallet .stars` + small note | `/me` balances (as a pattern, not stars) |
| Money flow tiles | `.flow div` (`i` label, `b` title, `p` text) | `/money` steps, `/brand` receipt, `/me` compute budget |
| Plate parade | `.parade`, `.held`, `.sign` with the species sign kit and the `AD` tab | `/brand` preview, the live line on `/live` |
| Park yard + walkers | `.park`, `.walker .tag`, `.parkrules` | `/park` (the home page section is samples; the page shows real pets) |
| Room | `.room`, `.decor` | not needed on these pages |
| Word fill | `.words` | not needed |
| Big end | `.end` (wobbling pet canvas + giant title + CTAs) | success screens ("Your campaign is live.", "This Mac is paired.") |
| Footer | `footer` (mono, two spans, space-between) | shared footer |
| Toast | `.toast` (mono, accent, `aria-live`) | "Link copied" |

Sprites: `public/pets/<id>.webp` (v6 sheets, 8 columns of 192x208 cells, 39 rows) and `public/site/sprites/<id>.json`.
On the home page, `class Pet` in `site.js` draws them to canvas. The app pages draw sprites with CSS:
- `components/PetArt.tsx` (Ink only)
- `components/Species.tsx` (any species; rows `idle 5`, `greet 3`, `celebrate 4`, `backflip 35`)

`/me` and `/pet` don't know which species the pet is. They always draw the Ink sprite.

### A6. Rules every page keeps

- **No chain names in product copy.** The UI says "purse", "earned", "paid for thinking". Account IDs and hashes
  appear only in Advanced views, docs and the README (`CLAUDE.md`; spec D §11: "User-facing copy names no chain. IDs and
  hashes are the only jargon allowed.").
  - Allowed to be technical:
    - `/brand`: brands pay with the token, so amounts may name it. This was a deliberate audit decision (`docs/PLAN_1.0.md`, Audit).
    - `/pair`: a one-time signing step.
    - An "Advanced" or "Proof" area on any page.
  - Pages that break the rule today:
    - `/live`: "Live on NEAR testnet", "Views settle on NEAR", "NEAR AI Cloud".
    - The hero caption: "Live now on NEAR testnet".
    - `/me`: "NEAR AI", "a fixed per-tier rate in NEAR".
- **Never fake.**
  - A dash `—` means unknown. Never show a zero for unknown ("a zero is a claim").
  - Seeded data is labelled on screen as seeded.
  - Example content is labelled "example".
  - If the server or the chain can't be read, say so in plain words.
  - Nothing may suggest a payment happened before a receipt exists.
- **Sponsored lines are always labelled.**
  - The plate carries an `AD` tab (R2 §2), and screen readers read "Sponsored, <brand>: <line>".
  - The web preview today uses a "Sponsored" tag (`components/HookTicker.tsx`).
  - Lines are 6-40 characters, shown whole, never truncated or scrolled.
  - The plate is never mirrored.
- **Proof stays visible.**
  - Every receipt is a tx link (opens the explorer in a new tab).
  - Every AI call shows its request or completion ID.
  - Campaign pages link the public log and show `gremlo verify <id>`.
  - Hashes can be shortened (`abcd1234…ef56`), but they stay links and stay on the page, not behind a menu.
- **Accessibility.**
  - Every input keeps a visible label.
  - Errors use `role="alert"`, progress uses `role="status"`, and the budget meter uses `role="meter"` with values.
  - Contrast is at least 4.5:1 for text. Accent text on paper uses the paper-safe shade.
  - Focus rings are visible.
  - Reduced motion: sprites hold frame 0 and the scroll reveals are off.
  - Pet art is decorative (`aria-hidden`) unless it is a control.
- **Mobile.**
  - Every page works at 360px with a 16-20px gutter and no horizontal scroll.
  - Long IDs and hashes wrap (`word-break: break-all` today).
  - Forms are one column under 760px.

### A7. Bugs to fix in the redesign (found while writing this)

- `/money`, `/gallery` and `/park` each render their own `<main>` inside the layout's `<main>` (nested landmarks).
- Those three pages use a `.error` class that has no style, so their error text looks like body text. The other pages use `.bad`
  (ink text with a small Signal square).
- `/money` doesn't check the HTTP status. An error reply from the server shows dashes instead of the error message.
- The pet name rules differ:
  - Home page certificate: up to 14 characters, any case.
  - `/pet`: 2-24 lowercase letters, digits or dashes.

---

## Part B. Pages

### B1. `/pet`: Get your pet

**File:** `apps/web/app/(app)/pet/page.tsx`. **For:** a developer getting their first pet. Linked from the home page CTA
"Get your pet" and the "Hatch yours" section.

**Job:** prove you're one real person with World ID, then register a named pet with a payout account.

**Current layout:**

```
1. DETAILS  ›  2. PROVE YOU'RE HUMAN  ›  3. MOVE IN        (mono step strip; current step dark)
Get your pet                                              (h1)
One person, one pet. That stops fake views, so brands only pay real people.
────────────────────────────────────────
[ Connect wallet ]            or   Connected: owner.gremlo.testnet
PET NAME
mochi_______________________
mochi                                                     (mono echo of the lowercased name)
PAYOUT ACCOUNT
mochi.testnet_______________
The account the pet's earnings go to. It must already exist. Only you can change it later.
[ Prove you're a real person ]
Connect your wallet first.
```

**Content and data:**
- The step strip "1. Details › 2. Prove you're human › 3. Move in". The current step is highlighted.
  The registering, denied and error phases highlight no step.
- h1 "Get your pet". Lead: "One person, one pet. That stops fake views, so brands only pay real people."
- Connected account (mono): "Connected: <account>".
- Pet name: default "mochi", lowercased and echoed below in mono.
- Payout account: filled with the connected account on connect. Hint: "The account the pet's earnings go to. It must already exist. Only you can change it later."

**Actions and flow:**
1. **Connect wallet** opens the NEAR Connect picker (`@hot-labs/near-connect`, `lib/chain.ts connectWallet`).
   On failure the wallet's message is shown under the button.
2. **Prove you're a real person** (disabled until connected; label "Starting…" while busy). It checks these, in order:
   - "Connect your wallet first."
   - "Name: 2-24 letters, numbers or dashes." (`^[a-z0-9-]{2,24}$`)
   - "Payout must be an account id, like mochi.testnet." (NEAR account rules, 2-64 characters)
   - "World app ID / RP ID missing in .env." This is a setup error that users never see.
3. The server signs the World request (`GET /world/sign`). IDKit opens with the "orb" or "device" preset, and the signal is the
   owner account. This moves to the **scan** phase:
   - Staging: h2 "Verify with the World ID simulator", "Test mode: open simulator.worldcoin.org, then scan this code or paste the link below into it."
   - Production: h2 "Scan with World App", "Open World App and scan this code."
   - A 220px QR on white, a **Copy link** ghost button, and "Waiting for your phone…".
   - Polls every 2s, with a 3-minute timeout.
4. If the proof doesn't complete, the error phase shows "World ID didn't complete: <reason or 'cancelled'>".
5. **Registering** phase: "Verified. Checking the proof on our server and registering your pet…" (`POST /pets/register`).
6. **Done** phase: the pet sprite, h2 "<name> is moving into your notch.", then "Registered: <tx link>" and
   "Marked verified: <tx link>". If no hashes came back, it shows only "Registered.".
7. **Denied** phase (visible World denied path, a sponsor requirement): h2 "You already have a pet.", "World ID says this person
   has registered a pet before. Each human gets one, which is how brands know every impression comes from a real
   screen." and a **Back** button.
8. **Error** phase: the server message plus **Try again**. Messages the server can send:
   - "World proof rejected: it was made for a different NEAR account"
   - "World proof rejected: <code>"
   - "pet already registered" (the name is taken)
   - "Can't reach the Gremlo server at <url>. Is it running?"

**States to design:**
- Form: wallet not connected, then connected.
- Form with a validation error.
- Scan: staging and production.
- Registering.
- Done with hashes, and done without.
- Denied.
- Error: name taken, proof rejected, server down.

**Constraints:**
- The denied screen must stay clearly different from a generic error. It's the visible "one human, one pet" proof.
- The tx links stay visible on Done.
- Product copy: "NEAR" appears only through account IDs today, which is allowed. Keep it that way.
- The QR needs a white quiet zone in both themes.

**Reuse:** `.sec-head`; `.field`; `.btn.solid` and `.btn.ghost`.
- The notch in `think` state while waiting for the phone, then `egg` and `door` for registering.
- `.cert` for Done: the pet's name, "Hatched today", "First agent: —" until the Mac reports one.
- The `.grow` Egg stage art.

**What the spec says:**
- R4 §18: "Name taken: offer `mochi-2` or let the user pick. No auctions, no paid names." **Not implemented.** The page
  shows the raw "pet already registered".
- R3 §3 (Hatching) describes the egg in the notch on the Mac. The web page doesn't show an egg. The certificate idea is
  on the home page only.
- The page doesn't know or ask for a species. The Mac hatches it.

### B2. `/me`: Your pet

**Files:** `apps/web/app/(app)/me/Me.tsx` and `page.tsx` (share metadata). **For:** the pet owner, and anyone who opens a shared
`/me?pet=<name>` link.

**Job:** show how a pet is doing: what it earned, its level and streak, its mood and its compute budget, with proof.

**Current layout:**

```
YOUR PET                                                  (mono kicker)
How is your pet doing?     ← becomes the pet's name once loaded
PET NAME
mochi______________  [ Show ]
────────────────────────────────────────
(sprite)
THIS WEEK            | PAID BY BRANDS, ALL TIME | LEVEL
0.0042 for 12 views  | 0.03 for 80 views        | 3
STREAK               | VIEWS TODAY              | MOOD
4 days               | 5                        | Stable: ...
Earnings come from settlements in the vault, paid to byte.gremlo.testnet. The streak and level are just for fun ...
[ Share this week on X ]
────────────────────────────────────────
Compute budget
A share of every settlement (20%) stays in the vault as the pet's compute budget. Each AI call is charged ...
BUDGET LEFT | SPENT ON AI, ALL TIME | CHARGED TODAY      | RATE PER CALL
0.004       | 0.001                 | 0.0002 of 0.01/day | 0.0005 smart · 0.0001 cheap
WHEN | ACTION | MODEL | COMPLETION ID | CHARGE
Thu 13 Nov, 22:07 GMT+5:30 | hold | Qwen/... | chatcmpl-... | 8f3a2b1c…
```

**Content and data** (`GET /pets/:name`; money is yoctoNEAR strings; `null` means the chain couldn't be read):
- The name comes from `?pet=`, or the last name used (`localStorage` key `gremlo.pet`). Loading rewrites the URL to `/me?pet=<name>`.
- Seeded banner: "Seeded data on a local sandbox, not real money."
- This week: "<amount> for <n> views".
- Paid by brands, all time: "<amount> for <n> views", or "chain unreachable".
- Level: a number, or "unknown".
- Streak: "<n> day(s)", or "starts with your next session".
- Views today: a number.
- Mood: "<mood>: <reason>". The tiers are Thriving, Stable, Hungry and Asleep. Asleep says why.
- Proof line: "Earnings come from settlements in the vault, paid to <payout link>. The streak and level are just for fun
  and never change what you're paid."
- Compute budget:
  - Text: "A share of every settlement (<share>%) stays in the vault as the pet's compute budget. Each AI call is
    charged a fixed per-tier rate in NEAR, not the real USD bill from NEAR AI, with the call's completion id in the
    onchain log."
  - Values: Budget left; Spent on AI, all time; "<today> of <cap> a day"; Rate per call "<smart> smart · <cheap> cheap".
  - Unreadable: "Can't read the vault right now."
- Last thoughts table: When, Action, Model, Completion id, Charge (tx link, or "–").
- Available from the API but not shown: `walletBalance`, `computeBalance`, `owner`, `petKey`, `explorer`.

**Actions:**
- **Show** loads the pet. Its label is "Loading…" while busy. Errors appear under the form as the server message.
- **Share this week on X** opens an X intent: "My Gremlo pet <name> earned <amount> this week from <n> verified views while
  my coding agent worked. Level <n>, <n>-day streak." The link previews with `/me/card`.

**States to design:**
- No name yet (first visit).
- Loading.
- Unknown pet (404).
- Server down.
- Loaded with real data.
- Loaded but seeded.
- Chain unreadable: the earned and compute values are null.
- Compute budget empty: the pet is Asleep.
- No thoughts yet.
- Each mood tier: Thriving, Stable, Hungry, Asleep. Money overlays every state: full is bouncy, low is slow and thin, broke can't leave the notch.

**Constraints:**
- This is product copy, so no chain names. Today it says "NEAR AI", "in NEAR", "onchain" and "vault".
  Amounts show with no unit, which is right for product copy. Keep the unit off, or use the product's own word.
- Completion IDs and charge tx links must stay visible. They prove inference is paid from the pet's own budget.
  They can live in an "Advanced" or "Proof" block on the same page.
- Unknown values must show `—` (D §11). Today they show "unknown" or "chain unreachable". Change them to `—` with a
  one-line reason.
- The thoughts table must not scroll the page sideways on a phone. Use stacked rows under 760px.

**Reuse:**
- `.cert` or a big `.dsp` name as the header, with the real species sprite (needs the species from the server; see A5).
- `.grow` for the stage.
- `.flow` tiles for the numbers, and a meal bar (`.meals i`) for budget left against the daily cap.
- `.btn.ghost` for share.

**What the spec says:**
- R4 §18: "Balances show `—` until connected. Never a made-up number." **Partly:** null values aren't faked, but
  they read "unknown" instead of `—`.
- D §6 Growing up (stages from meals) has no web view yet.
- R4 §15: the weekly postcard is Mac-only and leaves out earnings. The `/me` share card is a separate thing that does show
  earnings.

### B3. `/me/card`: share image

**File:** `apps/web/app/(app)/me/card/route.tsx`. An OG image (1200x630), not a page.

**Current layout:**

```
GREMLO  [· SEEDED, NOT REAL]
mochi                                   (84px bold)
this week   0.0042 · 12 views
level       3
streak      4 days
Earned from sponsored hooks while a coding agent worked.   (Signal)
```

- It is drawn from the server's real numbers. An unknown pet returns a 404 and no card. A missing `?pet` returns a 400.
- Week earnings are rounded to 4 decimals with no unit. Level shows "?" when unknown.
- The colours are fixed: Paper background, Ink text, Signal line, `#6b6b6b` labels.

**To design:** a card that matches the new look, including the species sprite and its accent. It is rendered with
`next/og`, so it can only use flexbox, inline styles and fonts loaded into the route. The seeded label must stay.

### B4. `/brand`: Fund a campaign (console and dashboard)

**File:** `apps/web/app/(app)/brand/page.tsx`. **For:** brands. It is the largest page. A share link `/brand?c=<id>` opens straight on that
campaign's dashboard.

**Job:** write or pick up to four sponsored lines, fund the campaign from the brand's wallet, then watch views, settle,
top up, close and get refunded.

**Current layout:**

```
Fund a campaign
Your hook, carried across a developer's screen by a tiny pet while their AI agent works. Pay per real, verified view.
[ Connect wallet ]                       or   Paying from brand.testnet
──────────────────────────────────────── 01
Your product
WHAT IS IT?            Clearlog, log search for TypeScript teams
WHO IS IT FOR?         backend developers
OFFER (OPTIONAL)       first 1M logs free
PROOF POINTS (OPTIONAL, ONE PER LINE)
[textarea]
Hooks may only use numbers and claims from here. Promises of returns or profit are never allowed.
CALL TO ACTION | LINK
☐ These proof points are our own claims, and they're accurate.
[ Write my hooks ]
(pet) Writing 16 hooks… Then every hook is checked against your proof points. This can take up to two minutes. 37s
──────────────────────────────────────── 02
Pick 1 to 4 hooks
Picked 2 of 4. Traffic is even until each line has 2,000 sightings, then favours the lines developers open.
When should each line show? ...
  Logs, found. Try Clearlog free        [any time ▾]
HUMOUR
┌──────────────────────────────────────┐
│■ Logs, found. Try Clearlog free      │  ← picked = ink fill + Signal square
│ WRITTEN BY AI · chatcmpl-…    31/40  │
└──────────────────────────────────────┘
…one group per format…
▸ 3 hooks didn't pass the claim checks
WRITE YOUR OWN
[_____________________] [ Add ]
0/40
──────────────────────────────────────── 03
Budget
TOTAL BUDGET (NEAR) | PRICE PER VIEW (NEAR) | RUNS FOR (HOURS)
Ends Thu 14 Nov, 22:07 GMT+5:30. Views can still be paid for 1 hour after that; then the unspent budget is refunded.
EMAIL FOR BUDGET ALERTS AND A WEEKLY REPORT (OPTIONAL)
Only used to email you about this campaign. Never shown or shared.
███████████████████████████████████████  (the one Ink block)
█ 100                                   █
█ views, roughly, at this price. ...    █
█ [ Fund campaign ]                     █
█ Contract: vault.gremlo.testnet        █
███████████████████████████████████████
──────────────────────────────────────── 04
Your campaign
CAMPAIGN ID [ 1 ]  Shown after you fund, as Campaign #N.
[ Check ] [ Settle views ]
Budget 0.1 NEAR · spent 0.02 NEAR · left 0.08 NEAR
[▓▓▓▓░░░░░░░░░░░░] (meter)
ADD BUDGET (NEAR) [0.5] [ Top up ]
Running until Thu 14 Nov, 22:07 GMT+5:30.
HOOK | VIEWS | CLICKS | CLICK RATE
Every counted view is a signed report from a pet. Public log · check it yourself with gremlo verify 1
```

After funding, the page is replaced by a receipt:

```
CAMPAIGN #3 · LIVE
Your campaign is live.
Developers will see your hooks the next time their coding agent starts working. ...
   [SPONSORED] Logs, found. Try Clearlog free      (rotating, pet below)
   PREVIEW: WHAT DEVELOPERS SEE
BUDGET 0.1 NEAR | PRICE PER VIEW 0.001 NEAR | ESTIMATED VIEWS 100 (estimate)
ENDS Thu 14 Nov, 22:07 (views paid until 1 hour later, then the rest is refunded) | RECEIPT 0x12ab34cd…ef5678
[ View dashboard ] [ Copy share link ] [ Start another ]
```

**Content, actions and validation:**

*Wallet:* **Connect wallet** (NEAR Connect). When connected: "Paying from <account>" in mono. Wallet errors show under the button.

*01 Your product.* The fields and their limits:
- What is it? (160)
- Who is it for? (120)
- Offer (optional, 120)
- Proof points (optional, one per line, 600)
- Call to action (40)
- Link (300)
- The claims checkbox: "These proof points are our own claims, and they're accurate."

**Write my hooks** (relabelled "Write new hooks" once some exist; "Writing hooks…" while busy) checks, in order:
- "Say what your product is."
- "Say who it's for."
- "Add a call to action, like "Try it free"."
- "Add your https link; clicking the pet's sign opens it."
- "Confirm the proof points are your own, accurate claims."

It then calls `POST /campaigns/hooks`: 2 lines per format, 8 formats, each run through the claim checks. While it runs, the
pet, "Writing 16 hooks…" and a seconds counter show. On failure: "Couldn't write hooks: <msg>. Try again, or write your own below."
A 400 shows the server's message as is.

*02 Pick 1 to 4 hooks.* This card appears once there are hooks or a hooks error.
- Counter: "Picked <n> of 4. Traffic is even until each line has 2,000 sightings, then favours the lines developers open."
- Groups by format: Humour, Sarcasm, Irresistible offer, Question, Bold claim, Urgency, Mini story, Dev meme, Your own.
- Each line is a toggle button (`aria-pressed`). It shows "written by AI · <request id>" or "written by you", and "<len>/40".
- Unpicked lines disable once 4 are picked. The first line is picked automatically.
- A moment per picked line, with the intro "When should each line show? The pet works out the moment on the developer's Mac;
  nothing about their work is sent.". The options are "any time", "while tests run", "during a deploy" and "on a long run".
- Dropped lines: "<n> hooks didn't pass the claim checks", expandable to "<line> — <reason>". A reason can be
  "closed category: <name>".
- Write your own: max 40, Enter or **Add**.
  - Errors: "A line is 6 to 40 characters." and "That hook is already in the list."
  - Live counter "<n>/40". The over-limit style (`.count.over`) exists in CSS but isn't used.

*03 Budget.* The fields:
- Total budget (default 0.1)
- Price per view (default 0.001)
- Runs for, in hours (default 24)
- An optional email (254). Its note: "Only used to email you about this campaign. Never shown or shared."

The "Ends …" hint updates in the browser. The ink summary block shows the estimated views (budget ÷ price, or "–") with
"views, roughly, at this price. Any unspent budget is refunded when the campaign ends.". It also links the contract
("Contract: <vault id>").

**Fund campaign** is disabled until a wallet is connected, at least 1 line is picked and nothing is busy. Its label steps
through "Checking your hooks…", then "Confirm in your wallet…", then "Saving your hooks…". The checks, in order:
- "Connect your wallet first."
- The brief checks above.
- "Pick 1 to 4 hooks for the pet to rotate."
- "Budget and price must be numbers."
- "Price per view must be more than 0."
- "Budget must cover at least one view."
- "Duration must be more than 0 hours."

Then the steps:
1. The server runs the same checks before any money moves (`POST /campaigns/check`), and refuses here if they fail.
2. The wallet signs `create_campaign` with the budget as deposit.
3. The server saves the line text (`POST /campaigns`).

If step 3 fails after payment, the receipt shows: "Paid onchain, but the server didn't save your hooks: <msg>. Your budget is
safe; contact us with the receipt."

Hints under the button: "Connect your wallet at the top to fund." and "Pick at least 1 hooks first."

*Receipt (after funding).* It shows:
- The mono tag "Campaign #<id> · live" and the h1 "Your campaign is live.".
- The rotating preview with a "Sponsored" tag and the caption "Preview: what developers see".
- Budget, price per view, estimated views "(estimate)", the end time and the receipt tx link.

Its actions:
- **View dashboard**: loads the campaign and scrolls to 04.
- **Copy share link**: `/brand?c=<id>`. The label becomes "Link copied" for 2s.
- **Start another**.

*04 Your campaign (dashboard).* A campaign ID input with **Check** ("Checking…") and **Settle views** ("Settling onchain…").
The dashboard reads the vault directly and the server for stats. It shows:
- "Budget <b> NEAR · spent <s> NEAR · left <r> NEAR" and a meter. The meter turns Signal at 80% and above.
- At 50% and above: "<n>% of the budget is spent." At 100%: "Budget used up: your hooks have stopped showing." Before the end
  time, both add "Top up below to keep them running."
- **Top up** (only while running): "Add budget (NEAR)", then "Added <x> NEAR: <tx link>".
  - Errors: "Connect the wallet that created this campaign first." and "Enter an amount in NEAR, like 0.5."
- Status line, one of:
  - "Closed. Unspent budget was refunded."
  - "Running until <time>."
  - "Ended. Views can be settled until <time>; then it can be closed and refunded."
  - "Ended and the settlement window has passed. Close it to refund what's left."
- **Settle views** result:
  - "No views queued for this campaign yet."
  - "Paid <n> views, <amount> NEAR", plus " [seeded, local sandbox]" when seeded.
  - One line per pet: "<n> to pet <petKey>: <tx link>".
  - "Settlement stopped: <error>".
- Stats table: Hook #, Views, Clicks, Click rate. Empty: "No views yet. They appear here as developers' agents start working."
  The table shows the hook number, not the line text.
- "Best hook so far: #<n>, <x>% of views clicked."
- "<n> views in the fraud check (paid after <h>h)."
- "<n> views voided, not charged: <reason>."
- "<n> views waiting to be settled."
- "By moment: tests 120 · deploy (under 50 pets) · …"
- "Paused by reports: line <n>."
- "Budget alerts and the weekly report go to the email you gave."
- Proof line: "Every counted view is a signed report from a pet. Public log · check it yourself with `gremlo verify <id>`".
  Public log goes to `<server>/campaigns/<id>/log`.
- Arkiv mirror (only when the server has it on): "Mirrored on Arkiv. Campaign card <key…>, expires at Arkiv block <n>. <n>
  settlement receipts. Arkiv explorer". Before it's published: "Not on Arkiv yet. It's published when the campaign is saved."
- **Close and refund** (only once the settlement window has passed): "Closing…", then "Refunded <amount> NEAR: <tx link>".
- Lookup error: "Enter a campaign ID number, like 2." or the vault's message, such as "No campaign #<id> on <vault>.".

**States to design:**
- Wallet: not connected, connected.
- Brief: empty, with errors, writing (long wait with timer), hooks back, hooks failed, all dropped.
- Picking: 0, 1-3 and 4 picked (the rest disabled).
- Funding: checking, waiting on the wallet, saving, failed (wallet rejected, or the check refused), funded but not saved.
- Receipt.
- Dashboard, campaign: running, under 50% spent, 50-79%, 80%+, used up, ended inside the settle window, ended past
  the window, closed. Plus: lookup empty, not found, server stats unavailable (vault data only).
- Settlement: none queued, paid, seeded, stopped with an error.

**Constraints:**
- This page may name the token on amounts. It's the brand console (audit decision). Tx links, the contract link and
  `gremlo verify` must stay visible.
- Line rules: 6-40 characters, at most 4 lines, never truncated in the preview. The claims checkbox stays required
  before writing and before funding.
- Each AI line keeps its request ID next to it.
- "Sponsored"/`AD` labelling stays on every preview.
- The page is long. A step layout (01-04) is fine, but the dashboard must also work alone from a share link.
- The moment and by-moment wording must not suggest any data about developers' work leaves their Mac.

**Reuse:**
- `.sec-head` and `.field` for the brief.
- `.seg` for the moment picker and format filters.
- `.held` + `.sign` with the species sign kit and the `AD` tab for the preview, instead of the old `HookTicker` board.
- `.flow` tiles for the receipt.
- `.end` for "Your campaign is live.".
- The accent fill for the one primary action (Fund).

**What the spec says:**
- R2 §2: "Lines are 6–40 characters; the console enforces the limit. Never truncate or scroll a line." **Implemented.**
  Lines you write are checked in the browser, and AI lines are checked on the server.
- R2 §15 A/B: "Up to 4 lines per campaign. Even traffic until each line has 2,000 sightings, then Thompson sampling on
  'opened' ... Floor 5% per line. Clicks on the pet never count." **Implemented** (4 lines in the UI, sampling on the server).
- R2 §15 Moments: "Lines are tagged `tests | deploy | long run | any` ... Brands see sightings per line, and per moment only
  for buckets with at least 50 distinct pets." **Implemented.**
- R2 §15 Safety: "Verify the domain and a business payment. Every new line gets an automated policy check plus human
  review ... Closed categories ... 3 reports per 1,000 sightings auto-pauses a line." **Partly.** Closed categories and
  claim checks run automatically, and report pauses are shown. Domain and business-payment checks and human review are a
  process with no UI (PLAN M9).
- Round 2 build brief, step 5: "use `.held`, `.pet` and `.sign` from `tokens.css` on the website hero and the brand console
  preview." **Not implemented on the console.** The preview uses the old `HookTicker` board with the Ink sprite.
  The home page parade does use the sign kit.

### B5. `/park`: The pet park

**File:** `apps/web/app/(app)/park/page.tsx`. **For:** visitors and pet owners.

**Job:** show the real pets whose owners opted in, in random order, and let you send your pet to visit one.

**Current layout:**

```
The pet park
Pets whose owners chose to show them. Random order every time; nobody is ranked. Tap one to say hi.
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│ pet  │ │ pet  │ │ pet  │ │ pet  │       (grid of 140px tiles, idle frame)
│Mochi │ │ Bo   │ │ ...  │ │      │
│buddy · beanie │ ...
└──────┘
(tapped tile plays the greet row and shows "Send my pet to visit")
To join, turn on "Show my pet in the park" in the Mac app's settings. Leaving removes your pet at the next refresh.
```

**Content and data** (`GET /park`): each pet has exactly `{id, name, species, stage, outfit[]}`. The server shuffles them on every load.
- The tile shows the sprite (idle frame), the name, and "<stage> · <outfit, comma list>".
- Its label is "<name>, a <stage>".
- Empty: "Nobody is out right now."
- Error: "Can't reach the park right now."
- Footer copy: "To join, turn on "Show my pet in the park" in the Mac app's settings. Leaving removes your pet at the next
  refresh."

**Actions:**
- Tap a pet: it plays the greet row (8 frames) and shows the link **Send my pet to visit** (`gremlo://visit?to=<id>`).
  The link opens the Mac app. If the app isn't installed, nothing happens.

**States to design:** loading (nothing is shown today), empty, error, a few pets, many pets, tapped pet, phone width.

**Constraints:**
- No ranking, counts, "most active" or owner names (R4 §14). Random order.
- The link only works with the Mac app installed. Say so for visitors without it.
- No sponsored line ever appears in the park.
- The tile is a `<button>` that holds a link. That nesting is invalid HTML; fix it in the redesign.

**Reuse:** the home page `.park` yard (sky and grass, trees, stars), `.walker .tag` name tags and the `.parkrules` row.
The difference is that this page uses real pets, so drop the "These walkers are samples" line. Canvas `class Pet` can
play the learned trick rows: backflip 35, juggle 36, moonwalk 37 (R4 §1; the app adds the backflip jump arc and the moonwalk slide).

**What the spec says:**
- R4 §14: "A public page, opt-in, off by default. Each pet publishes only name, species, stage and today's outfit. Random order on every load:
  no ranking, no counts, no "most active". Tap a pet: it does a trick it has learned, and offers a visit. Leaving removes
  the pet at the next refresh." **Mostly implemented.** The tap plays the greet row, not a trick the pet learned. The
  payload doesn't say which tricks a pet knows.
- R4 §12 Guestbook: "The owner shares a visit link (or taps a pet in the park). If the host allows visits..." The visit
  is handled by the Mac app; the web page only hands off the link.

### B6. `/gallery`: Community species

**File:** `apps/web/app/(app)/gallery/page.tsx`. **For:** visitors and species creators.

**Job:** list community-drawn species that passed review, and show how to make one.

**Current layout:**

```
Community species
Pets drawn by the community. Each one passed machine checks and two human reviewers. Only reviewed species can hold a sponsored line.
• Sprout by ana
• ...
────────────────────────────────────────
Make one
  gremlo new my-pet
  gremlo validate my-pet
  gremlo preview my-pet
  gremlo submit my-pet --creator "your name"
Only art you made. Imports from other pet apps stay on your Mac as companions.
```

**Content and data** (`GET /gallery`): each species is `{id, name, creator, rows, at}`. Only listed species are returned.
- Each list item is "<name> by <creator>".
- There's no picture. The server stores the sheet, but the web doesn't show it.
- Empty: "None listed yet."
- Error: "Can't reach the gallery right now."

**Actions:** none today.

**States to design:** loading, empty (the likely state at launch), error, a few listed species, a species paused by reports
(the server hides it; decide whether to show "paused").

**Constraints:**
- Creators get credit, not a storefront. Nothing is sold, no prices, and no "buy" language (R2 §13).
- The CLI block is technical and fine as is.
- "Only reviewed species can hold a sponsored line" must stay.

**Reuse:** `.sec-head`, the home page `.rail` cards as the pattern for species cards (sprite, name, creator), and a mono
code block styled like the Notch Live `.term`.

**What the spec says:**
- R2 §13: "**Flow:** `gremlo new` → `validate` → `preview` → `submit` (a PR to `gremlo-pets`, or upload on the web) →
  review → gallery." Upload on the web is **not implemented**. Submitting goes through the CLI (`POST /gallery`).
- R2 §13: "Three reports pause new hatches of a species while it is re-checked." The server has `POST /gallery/<id>/report`.
- Round 2 build brief, Milestone 7 step 3: "**Web gallery:** credit for the creator, an install button, and a report button. Nothing is for sale."
  **Partly:** the creator gets credit, but the page has **no install button and no report button**.

### B7. `/money`: Where the money goes

**File:** `apps/web/app/(app)/money/page.tsx`. **For:** brands deciding to pay, judges, curious visitors.

**Job:** explain where a brand's money goes and show the live totals read from the vault.

**Current layout:**

```
Where the money goes
[SEEDED DATA: not real]
1. A brand pays per 1,000 sightings, up front, into the campaign.
2. The platform fee is — until the rate is published.
3. The rest goes to the pet's balance, one settlement per pet, each with a receipt.
4. Meals come first: part of each settlement feeds the pet's own compute budget, which pays for its thinking.
5. Surplus above a small reserve goes to the owner's payout account.
6. Unspent budget goes back to the brand when the campaign closes.
────────────────────────────────────────
So far
Campaigns 3 · pets 2 · settled sightings 140
Paid to pets 0.14 · paid for thinking 0.002
────────────────────────────────────────
A sighting counts only when
the plate is fully visible for 2 seconds or more, the screen is unlocked, not shared and not recorded, ...
```

**Content and data** (`GET /stats`):
- `campaigns`, `pets`, `settledViews`, `paidWei`, `computeChargedWei`, `seeded`.
- Amounts show with no unit. Unknown values show `—`.
- Seeded banner: "SEEDED DATA: not real".
- Error: "Can't read the totals right now."
- The sighting rule: "the plate is fully visible for 2 seconds or more, the screen is unlocked, not shared and not recorded,
  someone used the Mac in the last minute, and the pet is under 12 lines an hour. Every counted sighting is a signed report
  in the campaign's public log; `gremlo verify <campaign>` checks it against the bill."

**Actions:** none.

**States to design:** loading (dashes), loaded, seeded, error.

**Constraints:**
- No chain names. Today the copy has none, which is good.
- The fee stays `—` until it is published. Never a made-up rate.
- `gremlo verify` stays.
- This is the best page for judges to land on. A link to a real campaign's public log would help, but only to a real one.

**Reuse:**
- The home page Money section: `.sec-head` "It holds one line. That buys its lunch.", the `.parade` of plates and the `.flow` four tiles.
  The page's six steps map onto the tiles.
- Big `.dsp` numbers for the totals, counting up the way `LiveStats` does (with reduced motion respected).

**What the spec says:**
- R2 §16 Money, items 1-6. **Implemented**, with two wording differences to resolve:
  - Spec item 5 says "Surplus above a small reserve goes to the owner **weekly**". The page drops "weekly".
  - The spec's sighting rule ends "with **no repeat brand**". The page leaves that out.
- Round 2 build brief, Milestone 8 step 6: "**Money page:** the fee shows "—" until it is set. Unspent budget is refunded when a campaign ends." **Implemented.**
- R2 §16 Proofs (signed hourly ed25519 batches) is **implemented differently**. Each sighting report is P-256 signed and chained (PLAN M9).
  The page copy ("a signed report") is accurate either way.

### B8. `/pair`: Pair a Mac

**File:** `apps/web/app/(app)/pair/page.tsx`. **For:** the pet owner. The Mac app opens it ("Settings → Pair this Mac with my pet")
with `?pet=<name>&key=<device public key>`.

**Job:** have the owner's wallet sign one message so this Mac's Secure Enclave key can sign the pet's views and clicks.

**Current layout:**

```
PAIR A MAC
Pair this Mac with your pet          → "This Mac is paired." when done
Checking the link…                   (loading)
────────────────────────────────────────
(sprite)
PET            | DEVICE
mochi          | 3fa9c2e1b0d4a7f6
Pairing lets this Mac's Secure Enclave sign your pet's views and clicks, so nobody else can earn as your pet. You sign
one message (NEP-413) with the NEAR account that owns the pet; no transaction, no fee.
[ Approve pairing ]                  → "Approve in your wallet…"
```

**Content:**
- Pet name, and the device ID (the first 16 hex characters of SHA-256 over the key, mono).
- The pairing text above.
- Done: "Views, clicks and think calls from this Mac are now signed by its Secure Enclave." and "Device <id> paired to <pet>. You
  can close this tab."

**Actions:**
- **Approve pairing** connects the wallet if it isn't connected, then signs NEP-413:
  "Pair this device to my pet.\nPet: <pet>\nDevice: <device>". The recipient is the vault, and the message carries a fresh 32-byte nonce.
- Errors:
  - Bad link: "This link is missing the pet or the device key. Open it from the Gremlo menu: Settings → Pair this Mac with my pet."
  - Unknown pet: "No pet called "<name>" is registered. Register it first on Get your pet."
  - Wrong wallet (403): "This NEAR account isn't the pet's owner, or the key isn't a full-access key. Connect the account that registered the pet."
  - Anything else: the wallet's or server's message.

**States to design:** checking the link, bad link, unknown pet, ready, waiting on the wallet, wrong account, done.

**Constraints:**
- This page may stay technical (NEP-413, Secure Enclave, the account). It's a one-time security step. Keep the message
  text exactly as is: the server checks it byte for byte.
- "No transaction, no fee" must stay prominent, because people fear signing.
- Done should say clearly that the tab can be closed.

**Reuse:** a minimal bar, `.sec-head`, `.flow` tiles for Pet and Device, the notch `door` or `peek` state as the art, and `.end` for done.

**What the spec says:** nothing directly. The design export doesn't cover web pairing (phone pairing is D §10, Mac and phone).

### B9. `/live`: Live numbers (the old home page)

**File:** `apps/web/app/(app)/live/page.tsx`. **For:** judges and visitors who want the real numbers and a real AI call. Linked from the
home page footer as "Live numbers".

**Job:** show live totals from the vault, the line that is live right now, and a "try it" box that makes one real AI
call.

**Current layout:**

```
● LIVE ON NEAR TESTNET
Your agent makes you wait.
Gremlo makes the wait pay.          (Signal, display)        [SPONSORED] <live line or example>
A tiny pet lives behind a hidden door ...                     (pet strolling)
[ Get your pet ] [ Advertise to developers ]                  LIVE NOW ON NEAR TESTNET | EXAMPLE HOOKS
███████████████ notch reveal (ink band: door glows, pet drops) ███████████████
How it works        01 Your agent starts working | 02 It carries one hook | 03 Real views get paid
TRY IT  Type your product. Watch the pet pitch it.    YOUR PRODUCT [__________] [ Write hooks ]
LIVE FROM THE CHAIN
CAMPAIGNS FUNDED | VIEWS SETTLED ONCHAIN | PAID TO DEVELOPERS | VERIFIED PETS     (count up)
Read from the campaign vault's own totals. These numbers only grow with real use.
DEVELOPERS: Earn while your agent thinks. [Get your pet] | BRANDS (ink): Reach developers who block every banner. [Fund a campaign]
[ demo video loop ]
██ Signal band: Put your hook on the sign. ... [ Fund a campaign ] ██
```

**Content and data:**
- Live line (`GET /campaigns/active`): the live campaign's hooks with the caption "Live now on NEAR testnet". With no campaign,
  three example lines captioned "Example hooks".
- Stats (`GET /stats`): Campaigns funded, Views settled onchain, Paid to developers (NEAR, 4 decimals), Verified pets.
  "…" while loading, "–" when unreachable.
- TryHook (`POST /try`, rate-limited): the product input (min 3 characters, "Say what your product is first.").
  - While it runs: "Writing on NEAR AI Cloud… Real inference, usually 20 to 60 seconds."
  - The result: three lines on the sign, captioned "Example only · written by AI · request <id…>", plus a format/text list.
- Demo video `/demo.mp4`, autoplay, muted, looping.

**Constraints:**
- Today it breaks the no-chain-names rule in several places: "Live on NEAR testnet", "Views settle on NEAR",
  "NEAR AI Cloud", "Live from the chain".
- The home page now covers its storytelling, so most of it duplicates `/`.
- Keep: the live line, the live totals (dashes when unknown), and TryHook with its request ID and "Example only" label.

**Reuse:** `.sec-head`, the `.held` + `.sign` plate for the live line, big `.dsp` counters, `.field` + `.btn.solid` for TryHook.

**What the spec says:** nothing. It predates 1.0. The 1.0 site (R3 §5) replaced it as the home page.

---

## Part C. Technical pages: recommendation

| Page | Recommendation | Why |
|---|---|---|
| `/pair` | **Restyle lightly** | One-time security step opened from the Mac. New bar, tokens, both themes and the `.end` done screen. Keep the technical copy and the signed message exactly. |
| `/live` | **Restyle lightly, and trim** | The home page now tells the story. Keep it as a "Live numbers" proof page: the live line, the totals, TryHook. Drop the duplicated hero, how-it-works, split and band. Rewrite the copy without chain names, or label it as the technical page. |
| `/me/card` | **Restyle** | The share image should match the new look, so shared links look like the product. |
| `/gallery` | **Redesign fully** (small page) | It has no pictures, no install and no report. The spec asks for install and report buttons. |
| `/money` | **Redesign fully** | Judges and brands read it. It should feel like the home page Money section, with live numbers. |
| `/pet`, `/me`, `/brand`, `/park` | **Redesign fully** | These are the main product flows and still on the old look. |

---

## Part D. Open questions for the designer

1. **Theme default.** Should the app pages start dark like `/`, or follow System? Today `/` defaults to System. Which
   page-level surfaces (forms, tables) should sit on Carbon in dark mode, and on Bone in light?
2. **The notch in the shared bar.** Should it be live on every page (for example, `think` while a request runs), or a still logo
   off the home page?
3. **Species on `/me` and `/pet`.** The server doesn't return a species for a pet yet. Design for both: a species-coloured
   page when it's known, and the Gremlo default when it isn't.
4. **`/brand` length.** One long page, or steps with a sticky summary? The dashboard must still open alone from `/brand?c=<id>`.
5. **Resolve the spec mismatches in A3** (radius, accent text in light mode) once for all pages.
