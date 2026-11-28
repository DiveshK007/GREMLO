// Shared server state: the store and how it is saved, the environment, the vault types, request helpers and the
// device-signature check. The route modules (routes/*.ts) import from here; index.ts only wires them to HTTP.

import { type IncomingMessage } from "node:http";
import { existsSync, readFileSync, mkdirSync, appendFileSync } from "node:fs";
import { seeded } from "./chain.ts";
import { type Pending } from "./batch.ts";
import { bad, errText, HttpError, type PetRecord } from "./register.ts";
import { type Brief } from "./campaigns.ts";
import { makeReserve } from "./reserve.ts";
import { pruneStamps } from "./prune.ts";
import { makeSaver } from "./saver.ts";
import { type Thought } from "./thoughts.ts";
import { canonical, checkSigned } from "./auth.ts";
import { nextEntry, type LogEntry, type MomentBucket } from "./trust.ts";
import { type Park, type Relay, type Visit } from "./social.ts";
import { type Submission } from "./gallery.ts";
import { type Mailbox } from "./phone.ts";
import { type Held } from "./fraud.ts";
import { type Payout } from "./mail.ts";

type Store = {
  pets: Record<string, PetRecord>; // keyed by name
  nullifiers: string[];
  pending: Record<string, Pending>; // campaign id -> pet key -> count
  lines: Record<string, string>; // lineHash -> ad line text (the chain only stores the hash)
  brands: Record<string, string>; // brand address -> display name
  today: Record<string, { day: string; count: number }>; // pet key -> impressions accepted today (UTC)
  thoughts: Record<string, Thought[]>; // pet key -> last NEAR AI decisions with completion ids
  lastImpression: Record<string, number>; // "campaignId:petKey" -> ms of the last counted impression
  urls: Record<string, string>; // campaign id -> brand landing page (https)
  briefs: Record<string, Brief>; // campaign id -> the brand's brief (private, never served)
  hookViews: Record<string, number[]>; // campaign id -> counted impressions per hook index
  clicks: Record<string, number[]>; // campaign id -> deduped sign clicks per hook index
  lastClick: Record<string, number>; // "campaignId:petKey" -> ms of the last counted click
  days: Record<string, string[]>; // pet key -> recent UTC days with a hook event or a counted view (streaks)
  payouts: Payout[]; // settlements this server sent, newest last (weekly numbers); the chain stays the record
  emails: Record<string, string>; // campaign id -> brand email for alerts (private, never served)
  alerted: Record<string, number>; // campaign id -> last budget alert level emailed
  reported: Record<string, number>; // campaign id -> ms of the last weekly report
  held: Record<string, Held[]>; // campaign id -> views waiting out the holdback, bucketed by pet, hour and network
  voided: Record<string, Record<string, number>>; // campaign id -> reason -> views voided by the fraud rules
  moments: Record<string, string[]>; // campaign id -> moment tag per line (tests | deploy | long run | any)
  momentViews: Record<string, Record<string, MomentBucket>>; // campaign id -> moment -> sightings and distinct pets
  reports: Record<string, number[]>; // campaign id -> "Report" count per line
  logs?: Record<string, LogEntry[]>; // older stores kept the log inline; moved to LOG_DIR at startup
  settledViews?: number; // running total of views this server settled (for /stats without an RPC per pet)
  logHeads: Record<string, { i: number; hash: string }>; // campaign id -> last public-log entry (the log itself is in LOG_DIR)
  park: Park; // opt-in pet park: exactly {id, name, species, stage, outfit}
  parkTokens: Record<string, string>; // park id -> secret the owner's Mac uses to read its visits
  visits: Visit[]; // guestbook visits waiting for the host's Mac (24 h)
  relay: Relay; // team relay: members and visits (24 h)
  gallery: Submission[]; // community species: review -> listed (or paused by reports)
  galleryReviews: Record<string, string[]>; // submission id -> reviewers who played every row
  phones: Record<string, Mailbox>; // pairing channel -> sealed state and answers (the server can't read them)
};

// shortcut: one JSON file, one process; fine for a single instance on a persistent volume (STORE_PATH).
// Move to Postgres (PLAN_V2 A2) before running a second instance.
const STORE_FILE = process.env.STORE_PATH ?? new URL("../data.json", import.meta.url).pathname;
export const store: Store = {
  pets: {},
  nullifiers: [],
  pending: {},
  lines: {},
  brands: {},
  today: {},
  thoughts: {},
  lastImpression: {},
  urls: {},
  briefs: {},
  hookViews: {},
  clicks: {},
  lastClick: {},
  days: {},
  payouts: [],
  emails: {},
  alerted: {},
  reported: {},
  held: {},
  voided: {},
  moments: {},
  momentViews: {},
  reports: {},
  logHeads: {},
  park: {},
  parkTokens: {},
  visits: [],
  relay: { members: {}, visits: [] },
  gallery: [],
  galleryReviews: {},
  phones: {},
  ...(existsSync(STORE_FILE) ? JSON.parse(readFileSync(STORE_FILE, "utf8")) : {}),
};
export const utcDay = () => new Date().toISOString().slice(0, 10);
// each campaign's public log is an append-only file, so the store stays small and save() stays fast
const LOG_DIR = process.env.LOG_DIR ?? new URL("../logs", import.meta.url).pathname;
mkdirSync(LOG_DIR, { recursive: true });
export const logFile = (id: string) => `${LOG_DIR}/campaign-${id}.jsonl`;
export function appendLog(id: string, e: Omit<LogEntry, "i" | "prev" | "hash">) {
  const entry = nextEntry(store.logHeads[id] ?? null, e);
  appendFileSync(logFile(id), JSON.stringify(entry) + "\n");
  store.logHeads[id] = { i: entry.i, hash: entry.hash };
}
for (const [id, list] of Object.entries(store.logs ?? {})) {
  if (!existsSync(logFile(id))) {
    for (const e of list) appendFileSync(logFile(id), JSON.stringify(e) + "\n");
  }
  const last = list.at(-1);
  if (last) store.logHeads[id] = { i: last.i, hash: last.hash };
}
delete store.logs;
store.settledViews ??= store.payouts.reduce((a, p) => a + p.views, 0);
// write-then-rename (so a crash mid-write never leaves a truncated store). save() coalesces a burst into one write
// 250 ms later; saveNow() is for money, line text, pairing and the log head: a crash must not lose those.
const saver = makeSaver(STORE_FILE, () => store);
export const save = saver.save,
  saveNow = saver.saveNow;
for (const sig of ["SIGTERM", "SIGINT"] as const)
  process.on(sig, () => {
    saver.flush();
    process.exit(0);
  });
process.on("beforeExit", saver.flush);

export const REQUIRE_SIGNED = process.env.REQUIRE_SIGNED === "1"; // production: views, think and clicks must be device-signed
/** The visitor's IP; behind a host proxy (TRUST_PROXY=1) it comes from the proxy's header, not the socket. */
export const clientIp = (req: IncomingMessage) => {
  if (process.env.TRUST_PROXY === "1") {
    const h = req.headers["fly-client-ip"] ?? req.headers["x-real-ip"] ?? String(req.headers["x-forwarded-for"] ?? "").split(",")[0];
    if (typeof h === "string" && h.trim()) return h.trim();
  }
  return req.socket.remoteAddress ?? "unknown";
};
const rpId = process.env.RP_ID,
  rpSigningKey = process.env.RP_SIGNING_KEY;
if (!rpId || !rpSigningKey) throw new Error("missing env RP_ID or RP_SIGNING_KEY");
export const RP_ID: string = rpId;
export const RP_SIGNING_KEY: string = rpSigningKey;
if (process.env.WORLD_API_BASE && !seeded) throw new Error("WORLD_API_BASE (a stub World verifier) is allowed on a local sandbox only");

const yocto = (name: string) => {
  const v = process.env[name];
  if (!v || !/^[0-9]+$/.test(v)) throw new Error(`missing or non-integer env ${name} (yoctoNEAR)`);
  return BigInt(v);
};
// A fixed per-tier rate charged onchain for each AI call; not the real USD bill from NEAR AI.
export const fees = { smart: yocto("COMPUTE_FEE_SMART_YOCTO"), cheap: yocto("COMPUTE_FEE_CHEAP_YOCTO") };
/** The vault's view of a pet (get_pet); amounts are yoctoNEAR decimal strings. */
export type OnchainPet = {
  owner: string;
  payout: string;
  verified: boolean;
  views: number;
  earned: string;
  compute_share_bps: number;
  daily_cap: string;
  compute_budget: string;
  compute_spent: string;
  charge_day: number;
  charged_today: string;
};
export type OnchainCampaign = { brand: string; budget: string; spent: string; rate: string; end_time: number; closed: boolean; line_hash: string };
export const nowS = () => BigInt(Math.floor(Date.now() / 1000));

export const errMsg = errText;
export const findPet = (key: string) => store.pets[key] ?? Object.values(store.pets).find((p) => p.petKey.toLowerCase() === key.toLowerCase());

export async function readRaw(req: IncomingMessage, max = 100_000) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > max) throw new HttpError(413, "body too large");
  }
  return raw;
}
export const parse = (raw: string) => {
  try {
    return raw ? JSON.parse(raw) : {};
  } catch {
    throw bad("invalid JSON");
  }
};
export async function readBody(req: IncomingMessage) {
  return parse(await readRaw(req));
}

// ---- device signatures (PLAN_V2 A3) ----
export const seenSigs = new Map<string, number>();
export const petByDevice = (key: string) => Object.values(store.pets).find((p) => p.devices?.includes(key));

/**
 * The pet a request is signed by, or null when unsigned. A pet with a paired device must sign: an unsigned
 * request for it is a 401, and a signed one must come from one of its own devices.
 */
export function signer(req: IncomingMessage, path: string, raw: string) {
  // Macs from before the rename send X-Notchi-*; read for one release
  const hdr = (n: string) => req.headers[`x-gremlo-${n}`] ?? req.headers[`x-notchi-${n}`];
  const key = hdr("key"),
    time = hdr("time"),
    sig = hdr("sig");
  if (typeof key !== "string" || typeof time !== "string" || typeof sig !== "string") return null;
  checkSigned({ key, time, sig, message: canonical(req.method ?? "GET", path, time, raw), now: Date.now(), seen: seenSigs });
  // an unpaired Mac signs anyway; that proves nothing more than no signature, so it counts as unsigned and
  // mustBeFrom decides (fine locally, refused with "pair this Mac" when REQUIRE_SIGNED=1)
  return petByDevice(key) ?? null;
}

export const reserve = makeReserve(); // pet -> compute held for AI calls in flight and charges not landed yet
/** pet key -> why its last settlement failed; cleared when one lands. In memory: the next worker pass refills it. */
export const settleErrors = new Map<string, string>();

export const str = (v: unknown, max = 64) => (typeof v === "string" ? v.slice(0, max) : undefined);

/** What a brand sees for one campaign: per-hook views and clicks, queued views, link. Brief stays private. */
export const HOLDBACK_HOURS = Number(process.env.HOLDBACK_HOURS ?? 0); // 24 in production (Dockerfile); 0 keeps local demos instant

/** A request address, parsed once. */
export type Url = { pathname: string; searchParams: URLSearchParams };
/** What a route module's handle() returns when the request is not one of its routes. */
export const NOT_HANDLED = Symbol("not handled");

export function housekeeping(now: number) {
  pruneStamps(seenSigs, now, 60 * 60_000);
}
