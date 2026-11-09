// JSON shapes the Mac app decodes. Amounts are wei as decimal strings.

export function campaignView(
  c: { id: bigint; brand: string; lineHash: string; rate: bigint },
  names: { lines: Record<string, string>; brands: Record<string, string>; urls?: Record<string, string> },
) {
  const text = names.lines[c.lineHash] ?? null; // the chain stores only the hash
  const hooks = text ? text.split("\n") : [];
  return {
    campaignId: c.id.toString(),
    line: hooks[0] ?? null, // first hook, for clients that show one line
    hooks,
    url: names.urls?.[c.id.toString()] ?? null,
    brand: names.brands[c.brand] ?? c.brand,
    ratePerImpression: c.rate.toString(),
  };
}

export type Thresholds = { thriving: bigint; stable: bigint; hungry: bigint };

export function moodFor(wei: bigint, t: Thresholds) {
  return wei >= t.thriving ? "thriving" : wei >= t.stable ? "stable" : wei >= t.hungry ? "hungry" : "asleep";
}

/** walletBalance null means the balance could not be read; the pet is then asleep and says why. */
export function petView(p: {
  name: string;
  walletBalance: bigint | null;
  thresholds: Thresholds;
  impressionsToday: number;
  seeded: boolean;
  lastThoughts?: { action: string; requestId: string; at: number }[];
  /** set when the pet feeds itself: its 0G credit drives the mood, and the last deposit is its meal */
  computeBalance?: bigint | null;
  lastMeal?: { amount: string; txHash: string; at: number } | null;
}) {
  const moodWei = p.computeBalance !== undefined ? p.computeBalance : p.walletBalance;
  return {
    name: p.name,
    mood: moodWei === null ? "asleep" : moodFor(moodWei, p.thresholds),
    moodReason: moodWei === null ? "can't read balance" : p.computeBalance !== undefined && moodFor(moodWei, p.thresholds) === "asleep" ? "0G credit used up; it eats when it earns" : null,
    walletBalance: p.walletBalance?.toString() ?? null,
    computeBalance: p.computeBalance?.toString() ?? null, // null unless the pet feeds itself
    impressionsToday: p.impressionsToday,
    lastThoughts: p.lastThoughts ?? [],
    lastMeal: p.lastMeal ?? null,
    seeded: p.seeded,
  };
}
