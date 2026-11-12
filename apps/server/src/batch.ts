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
 * Brand A/B (R2 §15): even traffic until every line has 2,000 sightings, then Thompson sampling on "opened"
 * per sighting, with a 5% floor per line. Returns `slots` hook indexes for the Mac to rotate through; the server
 * recomputes it hourly. Clicks on the pet never reach `clicks` (only the plate's link does).
 */
export function hookOrder(views: number[], clicks: number[], n: number, rand = Math.random, slots = 20, floor = 0.05, explore = 2000) {
  if (n <= 0) return [];
  const all = [...Array(n).keys()];
  if (all.some((i) => (views[i] ?? 0) < explore)) return [...Array(slots)].map((_, k) => k % n); // even until each line has enough
  const gamma = (k: number): number => {
    // Marsaglia-Tsang for k >= 1
    const d = k - 1 / 3, c = 1 / Math.sqrt(9 * d);
    for (;;) {
      let x: number, v: number;
      do {
        x = Math.sqrt(-2 * Math.log(rand() || 1e-12)) * Math.cos(2 * Math.PI * rand());
        v = 1 + c * x;
      } while (v <= 0);
      v = v * v * v;
      const u = rand() || 1e-12;
      if (Math.log(u) < 0.5 * x * x + d - d * v + d * Math.log(v)) return d * v;
    }
  };
  const beta = (a: number, b: number) => { const x = gamma(a), y = gamma(b); return x / (x + y); };
  // share of wins over many draws, then the floor, then whole slots
  const draws = 2000, wins = new Array(n).fill(0);
  for (let k = 0; k < draws; k++) {
    let best = 0, top = -1;
    for (const i of all) {
      const v = views[i] ?? 0, c = Math.min(clicks[i] ?? 0, v);
      const s = beta(1 + c, 1 + v - c);
      if (s > top) { top = s; best = i; }
    }
    wins[best]++;
  }
  const share = wins.map((w) => Math.max(w / draws, floor));
  const total = share.reduce((a, b) => a + b, 0);
  const count = share.map((x) => Math.max(1, Math.floor((x / total) * slots)));
  while (count.reduce((a, b) => a + b, 0) < slots) count[share.indexOf(Math.max(...share))]++;
  while (count.reduce((a, b) => a + b, 0) > slots) count[count.indexOf(Math.max(...count))]--;
  // interleave so the rotation isn't one line for 10 minutes straight
  const order: number[] = [];
  const left = [...count];
  while (order.length < slots) for (const i of all) if (left[i]-- > 0) order.push(i);
  return order.slice(0, slots);
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
