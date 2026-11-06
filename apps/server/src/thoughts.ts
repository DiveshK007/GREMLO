export type Thought = { action: string; requestId: string; at: number };

/** Newest first, last 10. A result without a real 0G request ID is not a thought and adds nothing. */
export function addThought(list: Thought[] = [], r: { action: string; requestId?: string | null }, nowMs = Date.now()) {
  if (!r.requestId) return list;
  return [{ action: r.action, requestId: r.requestId, at: Math.floor(nowMs / 1000) }, ...list].slice(0, 10);
}
