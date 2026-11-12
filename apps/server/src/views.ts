// JSON shapes the Mac app decodes. Amounts are yoctoNEAR as decimal strings.

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

export type Fees = { smart: bigint; cheap: bigint };
/** The pet's onchain compute state (vault get_pet), in yoctoNEAR. */
export type Compute = { budget: bigint; chargedToday: bigint; dailyCap: bigint };

export const EMPTY = "sleeping: compute budget empty";
export const CAPPED = "sleeping: daily compute cap reached";

/**
 * Mood and AI fee from the compute budget the vault holds for this pet. `inflight` is charges sent but not yet
 * landed. Thriving pays for the smart model, stable for the cheap one; hungry makes no AI call.
 */
export function computeMood(c: Compute | null, fees: Fees, inflight = 0n) {
  if (!c) return { mood: "asleep", reason: "can't read the chain", fee: null };
  const budget = c.budget - inflight, today = c.dailyCap - c.chargedToday - inflight;
  const room = budget < today ? budget : today;
  if (room >= fees.smart) return { mood: "thriving", reason: null, fee: fees.smart };
  if (room >= fees.cheap) return { mood: "stable", reason: null, fee: fees.cheap };
  return { mood: "hungry", reason: budget < fees.cheap ? EMPTY : CAPPED, fee: null };
}

/** walletBalance is the payout account (earnings); computeBalance is the onchain compute budget. null = unreadable. */
export function petView(p: {
  name: string;
  walletBalance: bigint | null;
  compute: Compute | null;
  fees: Fees;
  inflight?: bigint;
  impressionsToday: number;
  seeded: boolean;
  lastThoughts?: { action: string; requestId: string; at: number; model?: string; chargeTx?: string }[];
}) {
  const m = computeMood(p.compute, p.fees, p.inflight);
  return {
    name: p.name,
    mood: m.mood,
    moodReason: m.reason,
    walletBalance: p.walletBalance?.toString() ?? null,
    computeBalance: p.compute?.budget.toString() ?? null,
    impressionsToday: p.impressionsToday,
    lastThoughts: p.lastThoughts ?? [],
    seeded: p.seeded,
  };
}
