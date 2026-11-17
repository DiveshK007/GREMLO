/**
 * Compute held for AI calls that are in flight. The budget check and the hold happen in one synchronous step, so
 * two concurrent thoughts can't both spend the same budget; the hold comes off when the call fails or is billed.
 */
export function makeReserve() {
  const held = new Map<string, bigint>();
  return {
    held: (key: string) => held.get(key) ?? 0n,
    /** Holds `fee` if `available` (what the chain shows) still covers it after everything already held. */
    tryHold(key: string, available: bigint, fee: bigint) {
      const cur = held.get(key) ?? 0n;
      if (available - cur < fee) return false;
      held.set(key, cur + fee);
      return true;
    },
    release(key: string, fee: bigint) {
      const next = (held.get(key) ?? fee) - fee;
      if (next > 0n) held.set(key, next);
      else held.delete(key);
    },
  };
}
