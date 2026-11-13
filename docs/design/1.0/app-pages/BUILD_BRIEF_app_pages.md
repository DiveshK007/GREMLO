# Build brief: move the app pages to the 1.0 design

The spec is in `APP_PAGES_REDESIGN.md`. The visual reference is in `web/` (open `index.html`, then walk the states with the ● STATE button) and in `screens/`. Do the steps in order. Each step ends with every page still working.

1. **Tokens and theme.**
   - Replace `apps/web/app/tokens.css` and `docs/design/1.0/tokens.css` with `tokens.css`. Port `--accent-text` (declared on `body, [data-pet]`) into `site.css` as well.
   - Add the pre-paint theme script to the root layout (key `gremlo.theme`). Delete the "Gremlo v2" tokens.
2. **Shared shell.**
   - Move the bar, the phone menu sheet, the footer and the bar notch into `apps/web/app/(app)/layout.tsx`, and use the same bar on `/`. Markup and behaviour are in `web/app.js` (`shell`, `makeNotch`).
   - Add a `useNotch()` hook with `think / wait / done / egg / door` that pages call around their requests.
   - `/pair` uses the minimal variant.
   - The layout owns the only `<main>`.
3. **Components.**
   - Port `web/app.css` from `/* ---------- base */` down: `.panel .stage .mini-notch .steps .field .check .seg .bad .note .seeded .ex .pill .hash .meter .tbl .cert .grow .held/.sign .term .qr .end .park .walker .toast`.
   - Replace the CSS-sprite `PetArt`/`Species` with one canvas `<Pet species row fps scale/>` built from `class Pet`, plus a `<Plate species line brand/>` built from the `data-plate` mount (it sets the screen-reader label "Sponsored, <brand>: <line>").
4. **`/pet`.**
   - Build the states from §4.1 and the `.cert` done screen.
   - Add the name-taken suggestions (`GET /pets/:name` 404 means the name is free) and the single name rule `^[a-z0-9-]{2,24}$`.
   - Wire the notch: `wait` while scanning, `egg` while registering, `door` when done.
5. **`/me`.**
   - Unknown values become `—` with a one-line reason; apply the copy table in §3.
   - Species drives `data-pet` and the sprite, once the API returns `species`, `stage` and `meals`. Until then use the Gremlo default.
   - Money changes the sprite: thriving → celebrate row, hungry → idle at 2 fps, asleep → stays in the notch.
   - The thoughts table stacks into rows on phones.
6. **`/me/card`.** Copy `og/card.tsx` into `route.tsx`. Put `assets/stills/` in `public/pets/stills/` and the font files in `public/fonts/`.
7. **`/brand`.**
   - Two tabs; the sticky summary with the plate preview (replaces `HookTicker`); the phone bottom bar.
   - Use `.count.over` for the line counter.
   - Receipt with a rotating plate; the unsaved receipt.
   - The dashboard shows line text, which needs the stats change from §5.
8. **`/park`.**
   - The yard, walkers as buttons, the "Everyone out now" list, and the picked panel holding the visit link (no link inside a button).
   - Play a trick when the payload has `tricks`, otherwise the greet row.
9. **`/gallery`.**
   - Cards with sheet art, Install (`gremlo://install?species=`) and Report (`POST /gallery/:id/report`, with the dialog), and the paused card.
   - Fix the nested `<main>` and replace `.error` with `.bad`.
10. **`/money`.**
    - The six tiles, counters with reduced-motion respected, and the rule checklist.
    - Check `res.ok`; show the server's error.
    - Show the public log link only for a real campaign.
11. **`/pair`.** Restyle only. Keep the signed message byte-identical (snapshot-test the string).
12. **`/live`.** Trim to the live line, the totals and TryHook. Copy per §3. The network is named only in the technical footnote.

**Definition of done**
- Every state in `screens/` reproduced at 1440 and 390, in both themes.
- No horizontal scroll at 360px.
- axe passes, with 4.5:1 text contrast in both themes (accent text uses the paper-safe shade in Light).
- Reduced motion freezes sprites on frame 0.
- `grep -i "near\|onchain\|vault"` over product copy hits only `/brand`, `/pair`, account IDs and the `/live` technical footnote.
