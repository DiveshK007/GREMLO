// The pet's purse (R4 §18, contracts-accounts): a pet with one pays for each thought itself, from its own account,
// signed on the Mac with a key that can only call pay_inference, within caps its owner sets. The server never
// moves that money. It asks for the payment after each thought, checks the payment on chain before it counts,
// and stops paid thinking while a thought stays unpaid. Pure: the chain reads are in index.ts.

import type { Thought } from "./thoughts.ts";

export const BYTE_COST = 10n ** 19n; // yoctoNEAR per byte of storage
export const RESERVE = 5n * 10n ** 23n; // 0.5 NEAR the purse never spends (contracts-accounts/purse RESERVE)
/** How long a thought may stay unpaid before paid thinking stops (the Mac pays seconds after the thought). */
export const GRACE_MS = 10 * 60_000;

export type PurseView = { owner: string; providers: string[]; per_call: string; daily: string; spent_today: string; total_paid: string };

export const purseAccount = (pet: string, parent: string) => `${pet}.${parent}`;

/** What the purse can still spend: its balance minus the storage stake and the reserve, never below zero. */
export function spendable(amount: bigint, storageUsage: number) {
  const s = amount - BigInt(storageUsage) * BYTE_COST - RESERVE;
  return s > 0n ? s : 0n;
}

/** A purse counts for a pet only when the pet's owner owns it and it may pay this server's operator. */
export const purseFits = (v: PurseView | null, owner: string, operator: string) => !!v && v.owner === owner && v.providers.includes(operator);

/** The oldest thought still owed, if it's older than the grace period. */
export function overdue(list: Thought[] = [], nowMs = Date.now()) {
  return list.filter((t) => t.due && !t.chargeTx && nowMs - t.at * 1000 > GRACE_MS).sort((a, b) => a.at - b.at)[0] ?? null;
}
/** What's owed and not yet paid, so the mood doesn't promise a thought the purse can't cover. */
export const owed = (list: Thought[] = []) => list.reduce((n, t) => (t.due && !t.chargeTx ? n + BigInt(t.due) : n), 0n);

/**
 * True when a transaction is the purse paying exactly this: signed by the purse's own key, sent to the purse,
 * successful in every receipt, and logging paid_for_thinking with this provider, amount and request id.
 */
export function paymentMatches(outcome: any, want: { purse: string; provider: string; amount: string; requestId: string }) {
  const tx = outcome?.transaction;
  if (tx?.signer_id !== want.purse || tx?.receiver_id !== want.purse) return false;
  if (outcome?.status?.Failure || (outcome?.receipts_outcome ?? []).some((r: any) => r?.outcome?.status?.Failure)) return false;
  if (!outcome?.status || !("SuccessValue" in outcome.status || "SuccessReceiptId" in outcome.status)) return false;
  const logs: string[] = (outcome?.receipts_outcome ?? []).flatMap((r: any) => r?.outcome?.logs ?? []);
  return logs.some((l) => {
    if (!l.startsWith("EVENT_JSON:")) return false;
    try {
      const e = JSON.parse(l.slice(11));
      return e.standard === "gremlo" && e.event === "paid_for_thinking" && e.data?.provider === want.provider
        && String(e.data?.amount) === want.amount && e.data?.request_id === want.requestId;
    } catch { return false; }
  });
}
