export type Thought = { action: string; requestId: string; at: number; model?: string; chargeTx?: string;
  /** purse pets: the fee owed for this thought (yocto) and who it is paid to; chargeTx is set once the payment is checked */
  due?: string; payTo?: string };

/** Newest first, last 10. A result without a real NEAR AI request id is not a thought and adds nothing. */
export function addThought(list: Thought[] = [], r: { action: string; requestId?: string | null; model?: string }, nowMs = Date.now()) {
  if (!r.requestId) return list;
  return [{ action: r.action, requestId: r.requestId, at: Math.floor(nowMs / 1000), ...(r.model ? { model: r.model } : {}) }, ...list].slice(0, 10);
}
