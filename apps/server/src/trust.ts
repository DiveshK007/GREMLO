import { createHash } from "node:crypto";

// R2 §15-16: moments, reports that pause a line, and each campaign's public log of signed sighting reports.

export const MOMENTS = ["tests", "deploy", "long run", "any"] as const;
export type Moment = (typeof MOMENTS)[number];
export const MOMENT_MIN_PETS = 50;

/** One tag per line; anything unknown is "any". */
export const momentTags = (tags: unknown, lines: number): Moment[] =>
  [...Array(lines)].map((_, i) => (Array.isArray(tags) && MOMENTS.includes(tags[i]) ? tags[i] : "any"));

export type MomentBucket = { count: number; pets: string[] };
/** Records a sighting in its moment bucket; pets are kept as short hashes, only to count distinct ones. */
export function addMoment(b: Record<string, MomentBucket>, moment: string, petKey: string) {
  const m = MOMENTS.includes(moment as Moment) ? moment : "any";
  const bucket = (b[m] ??= { count: 0, pets: [] });
  bucket.count++;
  const h = createHash("sha256").update(petKey).digest("hex").slice(0, 12);
  if (!bucket.pets.includes(h)) bucket.pets.push(h);
}
/** What a brand sees: per-moment sightings only for buckets with at least 50 distinct pets. */
export const momentView = (b: Record<string, MomentBucket> = {}) =>
  Object.fromEntries(Object.entries(b).map(([m, v]) => [m, v.pets.length >= MOMENT_MIN_PETS ? v.count : null]));

/** 3 reports per 1,000 sightings (and at least 3) pause a line. */
export const pausedLines = (reports: number[] = [], views: number[] = []) =>
  reports.flatMap((r, i) => (r >= 3 && r * 1000 >= 3 * Math.max(views[i] ?? 0, 1) ? [i] : []));

// MARK: public log

export type LogEntry = {
  i: number;
  campaign: string;
  hour: number;
  counts: number[]; // sightings accepted from this report, per line
  pet: string; // anonymous pet id (hash of its onchain key)
  key: string | null; // the device's P-256 public key, or null for an unsigned local report
  time: string | null;
  sig: string | null;
  body: string; // the exact signed request body
  prev: string;
  hash: string;
};

const sha = (s: string) => createHash("sha256").update(s).digest("hex");
export const ZERO = "0".repeat(64);

/** The hash that chains an entry to the one before; `notchi verify` computes the same string. */
export const entryHash = (e: Omit<LogEntry, "hash">) =>
  sha([e.prev, e.i, e.campaign, e.hour, e.counts.join(","), e.pet, e.key ?? "", e.time ?? "", e.sig ?? "", sha(e.body)].join("|"));

export function appendEntry(log: LogEntry[], e: Omit<LogEntry, "i" | "prev" | "hash">) {
  const base = { ...e, i: log.length, prev: log.at(-1)?.hash ?? ZERO };
  const entry = { ...base, hash: entryHash(base) };
  log.push(entry);
  return entry;
}

export const anonPet = (petKey: string) => sha(`pet:${petKey}`).slice(0, 16);

/** Recomputes the chain; `checkSig` verifies one entry's device signature. */
export function verifyLog(log: LogEntry[], checkSig: (e: LogEntry) => boolean) {
  const problems: string[] = [];
  let prev = ZERO, total = 0;
  log.forEach((e, n) => {
    if (e.i !== n) problems.push(`entry ${n}: index ${e.i}`);
    if (e.prev !== prev) problems.push(`entry ${n}: broken chain`);
    const { hash, ...rest } = e;
    if (entryHash(rest) !== hash) problems.push(`entry ${n}: hash doesn't match`);
    if (!e.key) problems.push(`entry ${n}: unsigned`);
    else if (!checkSig(e)) problems.push(`entry ${n}: bad signature`);
    total += e.counts.reduce((a, b) => a + b, 0);
    prev = hash;
  });
  return { ok: problems.length === 0, total, problems };
}
