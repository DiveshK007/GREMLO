// JSON shapes the Mac app decodes. Amounts are wei as decimal strings.

export function campaignView(
  c: { id: bigint; brand: string; lineHash: string; rate: bigint },
  names: { lines: Record<string, string>; brands: Record<string, string> },
) {
  return {
    campaignId: c.id.toString(),
    line: names.lines[c.lineHash] ?? null, // the chain stores only the hash
    brand: names.brands[c.brand] ?? c.brand,
    ratePerImpression: c.rate.toString(),
  };
}

export function petView(p: {
  name: string;
  walletBalance: bigint;
  impressionsToday: number;
  seeded: boolean;
}) {
  return {
    name: p.name,
    // shortcut: brain does not report balances or thoughts to the server yet, so these stay
    // empty instead of invented; fill them when brain posts its compute balance and deposits
    mood: "asleep",
    walletBalance: p.walletBalance.toString(),
    computeBalance: null as string | null,
    impressionsToday: p.impressionsToday,
    lastThoughts: [] as { action: string; requestId: string; at: number }[],
    lastMeal: null as { amount: string; txHash: string; at: number } | null,
    seeded: p.seeded,
  };
}
