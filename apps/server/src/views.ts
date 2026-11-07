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
}) {
  return {
    name: p.name,
    mood: p.walletBalance === null ? "asleep" : moodFor(p.walletBalance, p.thresholds),
    moodReason: p.walletBalance === null ? "can't read balance" : null,
    walletBalance: p.walletBalance?.toString() ?? null,
    // shortcut: brain does not report its compute balance or meals yet, so these stay empty
    // instead of invented; fill them when brain posts its compute balance and deposits
    computeBalance: null as string | null,
    impressionsToday: p.impressionsToday,
    lastThoughts: p.lastThoughts ?? [],
    lastMeal: null as { amount: string; txHash: string; at: number } | null,
    seeded: p.seeded,
  };
}
