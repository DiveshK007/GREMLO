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
