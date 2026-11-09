/** Pending impression counts for one campaign, keyed by pet key address. */
export type Pending = Record<string, number>;

/**
 * Decide how many impressions to settle per pet so the total never exceeds what the
 * campaign has left. Pets are filled in key order so the result is deterministic;
 * whatever does not fit stays pending until the brand tops up.
 */
export function planSettlement(pending: Pending, rate: bigint, remaining: bigint) {
  if (rate <= 0n) throw new Error("rate must be positive");
  let budgetLeft = remaining / rate; // impressions the budget can still pay for
  const settle: { pet: string; count: number; amount: bigint }[] = [];
  const leftover: Pending = {};
  for (const pet of Object.keys(pending).sort()) {
    const want = BigInt(pending[pet]);
    const take = want < budgetLeft ? want : budgetLeft;
    budgetLeft -= take;
    if (take > 0n) settle.push({ pet, count: Number(take), amount: take * rate });
    if (want > take) leftover[pet] = Number(want - take);
  }
  return { settle, leftover };
}

/** One impression per pet per campaign per window (BUILD_GUIDE section 8). Records the time when it counts. */
export function countImpression(last: Record<string, number>, key: string, now: number, windowMs: number) {
  if (last[key] !== undefined && now - last[key] < windowMs) return false;
  last[key] = now;
  return true;
}

/**
 * Take settled impressions out of pending. A tx that was sent but not confirmed counts as paid: it may still
 * land, and the contract would pay a resend again. Worst case the pet is underpaid; the brand never pays twice.
 */
export function markSettled(pending: Pending, pet: string, count: number, outcome: "paid" | "unconfirmed" | "failed") {
  if (outcome === "failed") return;
  pending[pet] -= count;
  if (pending[pet] <= 0) delete pending[pet];
}

/**
 * Rotation order for a campaign's hooks (auto-optimise): Thompson sampling on click rate, so hooks that get
 * clicked are shown more, while every hook under `explore` views keeps at least `floor` of the slots so early
 * noise can't bury it. `rand` is injectable for tests.
 */
export function hookOrder(views: number[], clicks: number[], n: number, rand = Math.random, slots = 12, floor = 0.15, explore = 200) {
  const sample = (a: number, b: number) => {
    // Beta(a, b): normal approximation once there is enough data, otherwise ratio of gammas from exponentials
    if (a + b > 60) {
      const m = a / (a + b), sd = Math.sqrt((a * b) / ((a + b) ** 2 * (a + b + 1)));
      const z = Math.sqrt(-2 * Math.log(rand() || 1e-12)) * Math.cos(2 * Math.PI * rand());
      return m + sd * z;
    }
    const g = (k: number) => { let s = 0; for (let i = 0; i < Math.round(k); i++) s -= Math.log(rand() || 1e-12); return s || 1e-12; };
    const x = g(a), y = g(b);
    return x / (x + y);
  };
  // pooled prior worth 20 views at the campaign's average click rate: a new hook starts near average, not at 50%
  const tv = views.reduce((x, y) => x + (y ?? 0), 0), tc = clicks.reduce((x, y) => x + (y ?? 0), 0);
  const p = tv ? Math.min(tc / tv, 1) : 0.05, prior = 20;
  const order: number[] = [];
  for (let k = 0; k < slots; k++) {
    const young = [...Array(n).keys()].filter((i) => (views[i] ?? 0) < explore);
    if (young.length && rand() < Math.min(1, floor * young.length)) { order.push(young[Math.floor(rand() * young.length)]); continue; }
    let best = 0, bestScore = -1;
    for (let i = 0; i < n; i++) {
      const v = views[i] ?? 0, c = Math.min(clicks[i] ?? 0, v);
      const score = sample(1 + c + p * prior, 1 + v - c + (1 - p) * prior);
      if (score > bestScore) { bestScore = score; best = i; }
    }
    order.push(best);
  }
  return order;
}

/** Sliding-window rate limit: true (and recorded) if `key` has fewer than `limit` hits in the last `windowMs`. */
export function allow(hits: Map<string, number[]>, key: string, now: number, limit: number, windowMs: number) {
  const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
  if (recent.length >= limit) { hits.set(key, recent); return false; }
  recent.push(now);
  hits.set(key, recent);
  return true;
}

export const SETTLE_GRACE_S = 3600n; // CampaignVault.SETTLE_GRACE

/** What the background worker should do for one campaign right now. Pure, so it is tested without a chain. */
export function workFor(c: { closed: boolean; endTime: bigint; remaining: bigint }, pendingViews: number, now: bigint) {
  if (c.closed) return "none" as const;
  const graceEnd = c.endTime + SETTLE_GRACE_S;
  if (now <= graceEnd && pendingViews > 0) return "settle" as const; // the contract still pays
  if (now > graceEnd && c.remaining > 0n) return "refund" as const; // anyone may close; the brand gets the rest back
  return "none" as const;
}

export const DAILY_VIEW_CAP = 120; // per pet per UTC day; the Mac app stops showing hooks at the same number

/** Whether another view can count today for a pet that already has `today` counted views. */
export const underDailyCap = (today: number, cap = DAILY_VIEW_CAP) => today < cap;

const dayBefore = (d: string) => new Date(Date.parse(d) - 86_400_000).toISOString().slice(0, 10);
/** Recent UTC days the pet was active (a hook event or a counted view), oldest first, at most 60. */
export const markDay = (days: string[] = [], day: string) => (days.at(-1) === day ? days : [...days, day].slice(-60));
/** Consecutive active days ending today, or yesterday so the streak survives until you code today. Cosmetic only. */
export function streak(days: string[] = [], today: string) {
  let d = days.at(-1) === today ? today : dayBefore(today), n = 0;
  for (let i = days.length - 1; i >= 0 && days[i] === d; i--, n++) d = dayBefore(d);
  return n;
}
/** Level from views the chain has paid for: 1 at 0, 2 at 10, 3 at 40, 4 at 90... */
export const level = (paidViews: number) => Math.floor(Math.sqrt(paidViews / 10)) + 1;
