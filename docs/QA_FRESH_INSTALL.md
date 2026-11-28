# QA: the core loop on a fresh install

Run this on a real Mac against the hosted server, from a clean start, before each release. It walks one pet through
the whole loop: install, register, pair, a Claude Code run, a signed view, settlement after the holdback, a compute
budget above zero, a paid thought, and the pet showing up on the web.

The run takes two sittings. Views wait out a **24 h holdback** in production (`HOLDBACK_HOURS=24` in
`deploy/vm/gremlo-api.service`), and the worker settles every 10 minutes. So steps 1 to 8 are day 1, and steps 9 to 12
are day 2, at least 25 h later.

Write down as you go: the pet name, the time of the first counted view, and every tx hash and request ID you see.

## Where to look

| Place | How |
|---|---|
| **Popover** | Click the Gremlo icon in the menu bar. The **Health** group has the rows below. Amber means something to fix. |
| **Health rows** | `Server`, `This Mac`, `Counting views`, `Views`, `Last view`, `Compute budget`, and `Park` when the park is on. |
| **Mac log** | Quit Gremlo, then run `/Applications/Gremlo.app/Contents/MacOS/Gremlo` (or the `~/Applications` copy) in Terminal. Lines start with `view:`, `privacy:`, `migrate:`. Launched from Finder, the app's log goes nowhere. |
| **Server log** | On the EC2 box: `journalctl -u gremlo-api -f \| grep -E "<pet>\|worker\|release"`. |
| **Server state** | `curl -s https://16-4-100-95.sslip.io/pets/<pet> \| jq '{mood, moodReason, paired, impressionsToday, views, compute, paidViews}'` |
| **Health endpoint** | `curl -s https://16-4-100-95.sslip.io/health \| jq` should show `"ok": true`. |
| **Web** | `https://gremlo.vercel.app/me?pet=<pet>` (your pet), `/live` (the demo pet and totals), `/park`. |

## 0. Clean start

1. Quit Gremlo (popover → **Quit Gremlo**).
2. Delete the app and its settings:
   ```bash
   rm -rf /Applications/Gremlo.app ~/Applications/Gremlo.app
   defaults delete app.gremlo.mac; defaults delete Notchi; defaults delete app.notchi.mac   # "does not exist" is fine
   ```
   This also deletes the Secure Enclave key blob, so the Mac gets a **new device key**, the same as a real reinstall.
3. In `~/.claude/settings.json`, remove any `gremlo-hook.sh` entries, or leave them and check step 3 reconnects cleanly.
4. Check the server: `curl -s https://16-4-100-95.sslip.io/health | jq .ok` prints `true`. If not, read `reasons` first.
   Every step below depends on the server being healthy.

## 1. Install

The **Health** rows, the per-Mac pairing note and the view-refusal notes are newer than v1.0.2. Until a release after
1.0.2 ships, test the install path with the v1.0.2 dmg, then run steps 2 to 12 on a build from `main`
(`curl -fsSL https://raw.githubusercontent.com/DiveshK007/GREMLO/main/install.sh | bash`, which installs to
`~/Applications/Gremlo.app`). On 1.0.2 itself, use the server-state `curl` and the server log in place of the Health rows.
The server side of these fixes is live once it deploys from `main`.

**Do:** download `Gremlo-1.0.2.dmg` from the v1.0.2 release (the README link points there), check it, then drag it to Applications:
```bash
shasum -a 256 ~/Downloads/Gremlo-1.0.2.dmg   # 3907de71e6bd8c8f2c1f50ea2358a9e1e6b840984447206595fbfd70b7d7a04d
```
Open it. The first time: **System Settings → Privacy & Security → Open Anyway**.

**See:** the menu bar icon, then within 2 s the alert "Show sponsored lines and earn while you wait?". Press
**Turn on**. A pet appears as an egg.

| Failure | Meaning |
|---|---|
| Hash differs | Wrong file or a bad download. Stop. |
| "Gremlo is damaged" | Quarantine on an ad hoc build. Use Open Anyway, or `xattr -dr com.apple.quarantine /Applications/Gremlo.app`. |
| No sponsored-lines alert | Old settings survived step 0 (`defaults read app.gremlo.mac sponsored`). Lines stay off until Settings → Earning → Show sponsored lines. |
| Pressed **Not now** | Health shows `Counting views: no: sponsored lines are off`. Turn it on in Settings → Earning. |

## 2. Get a pet (register)

**Do:** go to `https://gremlo.vercel.app/pet`. **Connect wallet** (the owner account), type a pet name, enter a payout
account that already exists, press verify and finish World ID. Then in the Mac app: **Settings → Pet → Pet name**, type
the same name and press Return. Gremlo restarts.

**See:** the web page says "<name> is moving into your notch." After the restart, the popover header shows the name.
Health shows `Server: reachable`.

| Failure | Meaning |
|---|---|
| "<name> is taken" | Pick another name. Names are one per pet. |
| Popover: "<name> isn't registered yet" / Health `Server: doesn't know <name>` | The Mac's name doesn't match a registered pet. Check the spelling in Settings → Pet. |
| Popover header still says `mochi` | The name wasn't saved (you clicked away instead of pressing Return). `mochi` is the default and the demo pet. Never QA as it. |
| Health `Server: can't reach it` | Network or server down. Check `/health`. The pet lives locally and says so, but nothing is paid. |
| "You already have a pet." | This World ID already has one. One human, one pet. Use that pet's name. |

## 3. Connect Claude Code

**Do:** **Settings → General → Claude Code → Connect**.

**See:** the button changes to show it's connected. `~/.claude/settings.json` has `~/.gremlo/gremlo-hook.sh` entries.

| Failure | Meaning |
|---|---|
| Alert "Couldn't update Claude Code's settings" | `settings.json` isn't valid JSON. The app leaves it untouched. Fix the file and press Connect again. |

## 4. Pair this Mac

**Do:** the popover shows an amber "Not paired yet: views from this Mac don't count." with a **Pair** button. Press
it, connect the **owner's** wallet on the page that opens, and sign.

**See:** the page says "This Mac is paired." and "Device <id> paired to <pet>". Within 10 s, Health shows
`This Mac: paired` and the amber note is gone.

| Failure | Meaning |
|---|---|
| "This Mac isn't the one paired to <pet> (a reinstall or a new pet name needs a new pairing)" | Another key is paired: an older install, or the Mac was paired to a different name. Press Pair again. The server keeps up to 5 Macs and drops the oldest. In 1.0.2 this case showed nothing while every view got a 401. |
| "This Mac has no Secure Enclave, so its views can't count." | Intel Mac without a T2 chip. Views from it never count. Test on another Mac. |
| Pair page: "No pet called … is registered" | The name in Settings → Pet doesn't match. |
| Pair page: wallet error about the signer | You signed with a wallet that isn't the pet's owner. Use the account from step 2. |

## 5. Hatch

A fresh pet is an egg, and **an egg shows no lines, so no views count.** Health says
`Counting views: no: still an egg: it hatches after 50 tool calls`.

**Do:** either run Claude Code until 50 tool calls, or **option-click the egg** to hatch it now.

**See:** the hatch animation. The popover's stage changes from `egg` to `hatchling`.

## 6. Claude Code run, sign shows

**Do:** start Claude Code in any repo and give it a task that runs tools for at least a minute.

**See:** the door opens and the pet drops out ("on it"). While tools run, the pet holds the sign with the campaign's
line. The popover's "Now showing" has the same line and "by <brand>". Health: `Counting views: yes, while the agent works`.

| Failure (Health `Counting views: no: …`) | Meaning |
|---|---|
| `no campaign is running` | No active campaign on the server. `curl …/campaigns/active` returns `null`. Fund one at `/brand`. |
| `stream mode is on (it stays on after a restart)` | Settings → Privacy → Stream mode. It is saved, so it stays on after a reinstall that kept settings. |
| `focus is on` / `paused` | Focus (⌥⌘F) or pause (⌥⌘P, or a long press on the notch). End it from the popover. |
| `quiet hours, until 08:00` | Settings → Earning → Quiet hours, between 22:00 and 08:00. |
| `the daily limit is reached` | 120 views today already. |
| `demo mode is on` | The play icon in the popover header is red. Turn demo mode off. |
| `hidden during a screen share, meeting or full-screen video` | Expected. Stop the share or the call, or leave full screen. |
| No pet reaction at all | The hooks aren't firing. Check step 3, and that nothing else is on port 47474 (`lsof -i :47474`). |

## 7. View signed and counted

The Mac sends a view when the sign has been up for 5 s, on an unlocked screen, with input in the last 5 minutes. It
sends at most one a minute per campaign.

**See:** about 5 s after the sign appears, Health shows `Last view: counted at <time>` and `Views: 1 today · 1 on hold 24 h`.
Mac log: `view: posting campaign <id> …` then `view: server answered {"accepted":1,…`. Server log:
`view: <petKey> campaign <id> hook <n> counted; held 24h, then the worker settles it`.

| Failure | Meaning |
|---|---|
| Popover: "Last view not counted: …" with the server's reason | The server refused it, and the reason is its own words. For example "the sign was on screen under 5 seconds", or "device is paired to a different pet" (re-pair). |
| Health `Last view: not counted`, "one a minute per campaign, at most 120 a day" | The server's 60 s window or the daily cap. Normal if you watch closely. The next one counts. |
| `Views` stays at `0 today` and there's no `Last view` row | No view was sent. Check the `Counting views` row. Also: the screen was locked or idle over 5 minutes. |
| Server log: `refused: view not counted: …` | Same as the popover note. |

**Check the signature** (optional): `gremlo-cli verify <campaign id>` (in `Gremlo.app/Contents/MacOS/gremlo-cli`)
prints `ok: every report is signed by a paired device, the chain is unbroken, and the log matches the bill`.

## 8. End of day 1

Let the run finish. **See:** Stop makes it celebrate, then after the idle timeout it climbs back to the notch. Note the
time of the first counted view. It becomes payable 24 to 25 h later, because views are held in hour buckets.

**Health:** `Views: N today · N on hold 24 h`. Nothing is paid yet, and that's expected. The `on hold` count is the holdback.
It does not mean views are lost.

## 9. Settled after the holdback (day 2, 25 h+ later)

**Do:** wait for one worker pass (up to 10 min) after the 25 h mark.

**See:** server log, in order:
- `release: campaign <id>: N views now payable`
- `worker: campaign <id>: N payable, 0 held, job settle`
- `settle: campaign <id> paid <petKey> for N views (<amount> yoctoNEAR), tx <hash>`

Health: `on hold` drops, then `N paid today` appears. The pet eats (the "+… food" bubble). The popover's "Paid by
brands" shows the views. Record the tx hash and open it on testnet.nearblocks.io.

| Failure | Meaning |
|---|---|
| Popover: "Views can't be paid right now: pet …'s payout account … does not exist" | The payout account from step 2 is gone or mistyped. The owner sets a real one (`set_payout`). Until this fix it also stopped every pet sorted after this one from being paid. |
| Popover: "Views can't be paid right now: pet … isn't verified onchain" | Registration stopped before `set_verified`. Register again on `/pet`. It picks up where it stopped. |
| `N to pay` stays for more than 20 min | The worker isn't settling. `curl …/health`: `settlement worker: no good pass in … (last error: …)`, or `operator balance: under 0.5 NEAR`. |
| Server log: `fraud: campaign <id> voided N views` | Over 3 pets on one network in an hour, or views in more than 20 hours of one day. Expected for a farm. For a QA box it means other test pets share your Wi-Fi. |
| `/health`: `N views expired unpaid` | The campaign ended and its 1 h settlement window closed before the holdback ended. Use a campaign that runs past day 2. |

## 10. Compute budget > 0

**See:** Health `Compute budget: <amount> · 20% of each paid view` (20% is the default share), and the amount is above 0.
`curl …/pets/<pet> | jq .compute` shows `budget` above 0. The mood in the popover header is `thriving` or `stable`.

| Failure | Meaning |
|---|---|
| `Compute budget: 0.0000 · 0% of each paid view` (amber) | The owner set the compute share to 0. Every payment goes to the payout account, and the pet can never think. Set a share above 0. |
| Budget above 0 but mood `hungry` / "sleeping: daily compute cap reached" | The budget is there, but today's cap is used up. It resets at UTC midnight. |
| "sleeping: compute budget empty" | The settlement paid too little for one thought at the cheap fee. More views, or a higher rate. |

## 11. Pet thinks

**Do:** start another Claude Code run.

**See:** a speech bubble with what the AI said. The popover's "Last thoughts" shows the action and a completion ID
(click to copy). "Receipt for the last AI charge" opens the `charge_compute` tx. Server log:
`charge: <petKey> paid <fee> yoctoNEAR for completion <id>, tx <hash>`. The compute budget goes down by the fee.

| Failure (popover bottom line `Last think: …`) | Meaning |
|---|---|
| `think failed: HTTP 401 …pair this Mac…` | The Mac isn't paired (step 4). |
| `sleep: sleeping: compute budget empty (no AI call)` | Back to step 10. |
| `sleep: … (no AI call)` with "can't reach" in the reason | NEAR AI is unreachable. The pet safe-stops and says so. That is correct behaviour, so retry later. |
| `sleep: sleeping: its compute budget is committed to another thought` | A thought is still in flight. Wait for the next hook event. |
| No bubble and no change | Thoughts are limited to one at a time and 10 a minute, and are skipped while paused or still an egg. |

## 12. Visible on the web

**`/me?pet=<pet>`** (your pet): the mood, compute budget, paid views and last thoughts match the popover.
"No Mac is paired to <pet> yet" here means step 4 didn't land.

**`/live`** follows the demo pet (`NEXT_PUBLIC_DEMO_PET`, `mochi`), not yours. For your run, check the totals instead.
"Views settled" goes up by your N within a minute (`/stats` is cached 60 s), and "Live now" shows the same campaign line
as your sign.

**`/park`:** in the Mac app, **Settings → Team and park → Show my pet in the park**. The row's text then says
`Now: in the park while the app runs (gone 15 min after it quits)`, and the popover Health shows a `Park` row. Reload
`/park` and your pet is in the list (in random order).

| Failure | Meaning |
|---|---|
| Park `Now: joins once it hatches` | Still an egg (step 5). It joins at the next heartbeat after hatching, within 5 min. |
| Park `Now: couldn't join: …` | The server's words. After a 403 the app forgets its old park id and joins fresh at the next heartbeat. |
| Pet gone from `/park` | The app quit or slept for over 15 min. The park only lists pets whose app is running. This is by design. |

## Pass

Pass only if every step showed what it should, with no manual top-up and no restart of the server. Record:
pet name, first counted view time, settlement tx, charge tx, completion ID, and whether `/health` stayed `ok`.
