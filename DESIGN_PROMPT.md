# Gremlo: Claude Design prompt

Paste each prompt into Claude Design. Start with the first one (the hero: notch + pet). Do the rest in order once the look is right. Keep everything in one design file so the style stays consistent.

---

## Prompt 0: style and character (paste first)

Design system for **Gremlo**, a desktop AI pet for macOS that lives behind a tiny door in the MacBook notch and reacts to AI coding agents like Claude Code. It has to earn its own food: brands pay to put one short line on a sign the pet holds while the agent works, and that money pays for the pet's AI brain.

Character (original, not based on any existing character):
- A small round creature about 48 px tall on screen, with a soft bean-shaped body, two stubby legs, big dark eyes and a small mouth that shows its mood.
- Default colour: warm cream with a coral belly patch. Make two colour variants so users can pick (mint and lilac).
- Pixel-art friendly. It should read clearly at 32-48 px. Draw it at 2x for the design and give a 1x preview.
- It always carries a tiny wooden sign on a stick, which it raises while working.

Visual style:
- Cosy, playful and calm, not loud. Think indie Mac utility, not crypto dashboard.
- Rounded corners, soft shadows only on the floating popover, flat everywhere else.
- Light and dark mode for every web screen and the popover.
- Typeface: a clean rounded sans for UI, a monospace for request IDs and tx hashes.
- No crypto jargon in user-facing copy. Say "balance", "food", "paid", not "wallet", "gas", "on-chain", except on detail rows (IDs, hashes).
- Plain, short copy. No emoji.

Deliver: the character turnaround (front, side, back), the colour variants, a colour palette, type scale, and the sign component.

---

## Prompt 1: the notch and the pet (hero)

Show the top of a MacBook screen with the notch, at real size, in a dark desktop and a light desktop.

1. **The door:** a tiny arched door at the bottom edge of the notch, about 14 px wide, the same black as the notch so it looks built in. States: closed, glowing (pet is awake inside), open, locked (small padlock).
2. **Pet poses and frames.** Give each a 4-6 frame strip:
   - drops out of the door (fall + small bounce on landing)
   - walks along the bottom screen edge
   - climbs the right side of the screen (vertical walk)
   - walks along the top edge towards the notch, then goes through the door
   - working: stands still, raises the sign; the sign shows one line of text (max 40 characters), for example "Ship faster with Acme CI"
   - needs approval: jumps and waves a small red flag
   - waiting for you: taps foot, looks out at the user
   - done: celebrates with a little spin and sparkles
   - failed: trips, lands on its face, gets up with a sad face
   - asleep: curled up behind the half-open door, "z z"
3. **Mood variants** for walk and working:
   - Thriving: bouncy, rosy cheeks
   - Stable: normal
   - Hungry: thinner body, droopy eyes, slower bob
   - Asleep (broke): stays in the notch, a small speech bubble "out of food, earning soon"
4. **Speech bubble:** max 2 short lines, appears above the pet, fades after 3 s.

Show a storyboard row of the main sequence: door glows, door opens, pet drops out, raises the sign, approval flag, celebrates, climbs the wall, goes home through the door.

---

## Prompt 2: menu-bar popover

A macOS menu-bar popover, 320 px wide, opened from a small Gremlo head icon in the menu bar. Light and dark.

Contents, top to bottom:
- The pet avatar with its name `mochi.gremlo.eth` and a mood chip (Thriving / Stable / Hungry / Asleep).
- Two balances side by side: "Earned" (pet wallet) and "Food" (AI credit left), each with a small bar.
- "Now showing": the current ad line in the sign style, and the brand name.
- "Today": impressions count and earnings today.
- "Last thoughts": 5 rows, each a short action ("Raised the sign", "Asked for approval"), time, and a monospace request ID that copies on click.
- "Last meal": the latest top-up of its AI credit, amount, time, monospace tx hash with an external-link icon.
- Toggles: "Show sponsored lines", "Sounds".
- Footer: "Approve request" button (only when the pet is waiting for approval) and a settings gear.

Also show the popover in two edge states: the pet is asleep because it's broke, and "Can't reach 0G, sleeping safely".

---

## Prompt 3: web app, brand side

A small web app for brands (developer-tool companies). Desktop 1280 px plus a mobile view of each screen. Light and dark.

1. **Landing / hero:** headline "Your ad, held up by a tiny pet while developers wait on their AI agent." Sub: "Pay per real impression. Unspent budget comes back." CTA "Start a campaign". Show the pet holding a sign with a sample line.
2. **New campaign (checkout), one page:**
   - Field: "What do you sell?" (short brief, 1-2 sentences).
   - "Gremlo wrote these for you": 3 selectable line cards in the sign style, each with a tiny "written by AI · request ID" caption in monospace. Option to regenerate.
   - Budget, price per impression, end date. A live summary card: estimated impressions, "Any unspent budget is refunded when the campaign ends".
   - Pay button "Fund campaign". Then a confirmation state with a receipt: amount, campaign ID, a monospace tx hash with an explorer link.
3. **Campaign dashboard:** cards for impressions, spent, remaining, number of pets showing it. A simple line chart of impressions over time. A list of pets showing it (avatar, `name.gremlo.eth`, impressions), only verified pets. An ended campaign shows "Refunded 12.4 to you" with a tx hash.

---

## Prompt 4: web app, developer side

Same style. Desktop plus mobile.

1. **Get your pet:**
   - Step 1 "Download for Mac".
   - Step 2 "Prove you're a real person" with a World ID button. Short note: "One person, one pet. This stops fake views, so brands pay real people."
   - Step 3 "Name your pet": choose a colour variant, type a name, preview `mochi.gremlo.eth`.
   - Success: the pet waves, with "Mochi is moving into your notch."
2. **Denied state:** "You already have a pet." Friendly, clear, with a link to the existing pet. This is a key demo screen, so make it look intentional, not like an error.
3. **Approval request:** "Mochi wants to upgrade to its smartest brain for this session. Cost: 0.8 of its food." Buttons "Approve with World ID" and "Not now". Then the approved and denied result states.
4. **Public pet page** (`mochi.gremlo.eth`): large pet illustration in its current mood, live status ("Working with Claude Code", "Hungry", "Asleep"), earned total, meals eaten, and a small "Owned by a verified human" badge. A "Payout address can only be changed by the owner" note with a lock icon.

---

## Prompt 5: demo and pitch assets

- An opening title card: "Gremlo" with the pet peeking out of the notch door, and the line "Your coding agent makes you wait. Gremlo makes that wait pay for itself."
- One slide that shows the loop: brand pays, pet holds the sign, pet earns, pet eats (AI credit), pet thinks. Five simple icons with arrows.
- One slide "Each sponsor has one job": 0G (brain + food), World (real humans only), ENS (the leash).
- A 1200x630 social image.

---

## Notes for the team
- Characters: the demo may use any art, but the public repo, showcase and socials use only this original character.
- Export sprites as PNG frame strips at 1x and 2x for `apps/mac/`.
- Copy in the designs is placeholder. Replace numbers with real data in the build. Never ship fake balances or IDs in the demo flow.
