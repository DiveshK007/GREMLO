import { randomBytes } from "node:crypto";

// R2 §11 team relay, R4 §12 guestbook visits, R4 §14 pet park. Each keeps exactly the fields the spec lists.

const SPECIES = ["gremlo", "gremlo-pip", "gremlo-moss", "gremlo-gloop", "gremlo-byte", "gremlo-puff", "gremlo-wisp", "gremlo-tako"];
const STAGES = ["hatchling", "buddy", "elder"];
const ITEMS = ["party", "beanie", "scarf", "star", "bow", "cap", "glasses", "headphones", "flower", "shades", "crown", "wizard"];
import { HttpError } from "./register.ts";
const bad = (m: string) => new HttpError(400, m);

export type ParkPet = { id: string; name: string; species: string; stage: string; outfit: string[] };
/** The park stores exactly {id, name, species, stage, outfit}; anything else is dropped. */
export function parkPet(b: any): ParkPet {
  const id = String(b?.id ?? ""), name = String(b?.name ?? "").trim();
  if (!/^[a-f0-9]{16,32}$/.test(id)) throw bad("id must be the pet's random park id");
  if (!name || name.length > 24) throw bad("name is 1-24 characters");
  if (!SPECIES.includes(b?.species)) throw bad("unknown species");
  if (!STAGES.includes(b?.stage)) throw bad("unknown stage");
  const outfit = (Array.isArray(b?.outfit) ? b.outfit : []).filter((x: unknown) => ITEMS.includes(String(x))).slice(0, 3).map(String);
  return { id, name, species: b.species, stage: b.stage, outfit };
}
export const newParkId = () => randomBytes(12).toString("hex");

export const PARK_TTL_MS = 15 * 60_000; // leaving (or closing the app) removes the pet at the next refresh
export type Park = Record<string, { pet: ParkPet; seen: number }>;
/** Random order on every load: no ranking, no counts. */
export function parkList(p: Park, now: number, rand = Math.random) {
  for (const [k, v] of Object.entries(p)) if (now - v.seen > PARK_TTL_MS) delete p[k];
  const list = Object.values(p).map((v) => v.pet);
  for (let i = list.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [list[i], list[j]] = [list[j], list[i]]; }
  return list;
}

export type Visit = { to: string; from: Omit<ParkPet, "id">; at: number };
export const VISIT_TTL_MS = 24 * 3_600_000;

// MARK: team relay

export type Relay = { members: Record<string, number>; visits: RelayVisit[] };
export type RelayVisit = { team: string; from: string; to: string; species: string; pr: number | null; url: string | null; at: number; delivered: boolean };
export const RELAY_KEEP_MS = 24 * 3_600_000, RELAY_EXPIRE_MS = 30 * 60_000, RELAY_PER_HOUR = 3;

const team = (t: unknown) => { const s = String(t ?? ""); if (!/^[a-z0-9-]{6,40}$/.test(s)) throw bad("team code is 6-40 of a-z, 0-9, -"); return s; };
const handle = (h: unknown) => { const s = String(h ?? "").toLowerCase(); if (!/^[a-z0-9_-]{1,32}$/.test(s)) throw bad("handle is 1-32 of a-z, 0-9, _, -"); return s; };

/** Opt-in: a member joins (and stays joined while it polls) with the team code. */
export function relayJoin(r: Relay, b: any, now: number) {
  r.members[`${team(b?.team)}:${handle(b?.handle)}`] = now;
  return { ok: true };
}

/** Payload: team, sender handle, species, PR number, PR URL. Nothing else. Both sides must have joined. */
export function relaySend(r: Relay, b: any, now: number) {
  const t = team(b?.team), from = handle(b?.from), to = handle(b?.to);
  prune(r, now);
  if (!r.members[`${t}:${from}`] || !r.members[`${t}:${to}`]) throw bad("both of you need to join the team first");
  if (!SPECIES.includes(b?.species)) throw bad("unknown species");
  const pr = b?.pr == null ? null : Number(b.pr);
  if (pr !== null && !(Number.isInteger(pr) && pr > 0)) throw bad("pr must be a positive integer");
  const url = b?.url == null ? null : String(b.url);
  if (url !== null && !/^https:\/\/[a-z0-9.-]+\/[^\s]{0,300}$/i.test(url)) throw bad("url must be an https link");
  const recent = r.visits.filter((v) => v.team === t && v.to === to && now - v.at < 3_600_000).length;
  if (recent >= RELAY_PER_HOUR) throw new HttpError(429, "that teammate already had 3 visits this hour");
  r.visits.push({ team: t, from, to, species: b.species, pr, url, at: now, delivered: false });
  return { ok: true };
}

/** A member's waiting visits (under 30 min old), each delivered once. */
export function relayInbox(r: Relay, q: URLSearchParams, now: number) {
  const t = team(q.get("team")), me = handle(q.get("handle"));
  r.members[`${t}:${me}`] = now;
  prune(r, now);
  const out = r.visits.filter((v) => v.team === t && v.to === me && !v.delivered && now - v.at < RELAY_EXPIRE_MS);
  out.forEach((v) => (v.delivered = true));
  return out.map(({ from, species, pr, url, at }) => ({ from, species, pr, url, at }));
}

function prune(r: Relay, now: number) {
  r.visits = r.visits.filter((v) => now - v.at < RELAY_KEEP_MS);
  for (const [k, at] of Object.entries(r.members)) if (now - at > RELAY_KEEP_MS) delete r.members[k];
}
