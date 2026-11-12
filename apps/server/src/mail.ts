import { errText, HttpError } from "./register.ts";

const YOCTO = 10n ** 24n;
/** yoctoNEAR to an exact decimal string, trailing zeros dropped. */
const near = (y: bigint) => `${y / YOCTO}${(y % YOCTO).toString().padStart(24, "0").replace(/0+$/, "").replace(/^(?=.)/, ".")}`;

// Brand emails: budget alerts at 50/80/100% and a weekly report. Off unless RESEND_API_KEY and MAIL_FROM are set.
// The address is private: stored on the server only, never served back, never on Arkiv.

export const ALERT_LEVELS = [50, 80, 100];
export const WEEK_MS = 7 * 86_400_000;

/** The highest alert level reached and not yet sent, or 0. `sent` is the last level already emailed. */
export const alertDue = (pct: number, sent: number) => ALERT_LEVELS.filter((l) => pct >= l && l > sent).at(-1) ?? 0;

/** Spent as a whole percent of budget, integer math on wei. */
export const usedPct = (spent: bigint, budget: bigint) => (budget > 0n ? Number((spent * 100n) / budget) : 0);

/** Best hook by click rate among hooks with at least `minViews` views; null until one qualifies. */
export function bestHook(views: number[], clicks: number[], minViews = 20) {
  let best: number | null = null;
  views.forEach((v, i) => {
    if (v >= minViews && (best === null || (clicks[i] ?? 0) / v > (clicks[best] ?? 0) / views[best])) best = i;
  });
  return best as number | null;
}

/** Optional brand email from the web form: trimmed, 254 chars max, one plain address. */
export function checkEmail(v: unknown) {
  if (v === undefined || v === null || v === "") return undefined;
  const s = String(v).trim();
  if (s.length > 254 || !/^[^\s@<>,;]+@[^\s@<>,;]+\.[a-z]{2,}$/i.test(s)) throw new HttpError(400, "that email address doesn't look right");
  return s;
}

export type Payout = { at: number; id: string; pet: string; views: number; wei: string; tx?: string }; // tx: the settlement, the pet's meal receipt
/** Payouts this server made since `since` (ms), filtered by `match`. */
export function sumSince(payouts: Payout[], since: number, match: (p: Payout) => boolean) {
  return payouts.filter((p) => p.at >= since && match(p)).reduce((a, p) => ({ views: a.views + p.views, wei: a.wei + BigInt(p.wei) }), { views: 0, wei: 0n });
}

export function weeklyReport(c: { id: string; hooks: string[]; views: number[]; clicks: number[]; spent: bigint; budget: bigint; humans: number; link: string }) {
  const views = c.views.reduce((a, b) => a + b, 0), clicks = c.clicks.reduce((a, b) => a + b, 0);
  const best = bestHook(c.views, c.clicks);
  return [
    `Campaign #${c.id}, so far:`,
    `${views} views from ${c.humans} verified ${c.humans === 1 ? "human" : "humans"}, ${clicks} clicks.`,
    `Spent ${near(c.spent)} of ${near(c.budget)} NEAR (${usedPct(c.spent, c.budget)}%).`,
    best === null ? "No hook has 20 views yet, so there's no winner." : `Best hook: "${c.hooks[best] ?? `#${best + 1}`}" (${((c.clicks[best] / c.views[best]) * 100).toFixed(1)}% click rate).`,
    "",
    `Dashboard: ${c.link}`,
  ].join("\n");
}

const key = process.env.RESEND_API_KEY, from = process.env.MAIL_FROM;
export const mailOn = !!(key && from);

/** Sends a plain-text email; true only when the provider accepted it. Failures are logged, never thrown. */
export async function sendMail(to: string, subject: string, text: string) {
  if (!mailOn) return false;
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify({ from, to, subject, text }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!r.ok) console.error(`mail: ${subject}: ${r.status} ${(await r.text()).slice(0, 200)}`);
    return r.ok;
  } catch (e) {
    console.error(`mail: api.resend.com ${subject}: ${errText(e)}`);
    return false;
  }
}
