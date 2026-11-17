/** Housekeeping for the in-memory rate-limit maps and replay sets, which would otherwise only ever grow. */

/** Drops keys whose newest hit is older than `maxAgeMs` (use the longest window any limit on this map uses). */
export function pruneHits(hits: Map<string, number[]>, now: number, maxAgeMs: number) {
  for (const [k, list] of hits) if (!list.length || now - list[list.length - 1] > maxAgeMs) hits.delete(k);
}
/** Drops entries stamped more than `maxAgeMs` ago. */
export function pruneStamps(stamps: Map<string, number>, now: number, maxAgeMs: number) {
  for (const [k, at] of stamps) if (now - at > maxAgeMs) stamps.delete(k);
}
/** Keeps a set at `max` entries by dropping the oldest (a Set iterates in insertion order). */
export function capSet(set: Set<string>, max: number) {
  for (const k of set) { if (set.size <= max) break; set.delete(k); }
}
