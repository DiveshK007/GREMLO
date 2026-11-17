// The opt-in pet park and guestbook visits.

import { type IncomingMessage } from "node:http";
import { allow } from "../batch.ts";
import { HttpError } from "../register.ts";
import { pruneHits } from "../prune.ts";
import { randomBytes } from "node:crypto";
import { newParkId, parkList, parkPet, VISIT_TTL_MS } from "../social.ts";
import { type Body, type Loose } from "../json.ts";
import { NOT_HANDLED, type Url, clientIp, readBody, save, store, str } from "../state.ts";

const parkHits = new Map<string, number[]>();
function joinPark(req: IncomingMessage, b: Body) {
  if (!allow(parkHits, clientIp(req), Date.now(), 30, 3_600_000)) throw new HttpError(429, "slow down");
  const pet = parkPet({ ...b, id: b?.id || newParkId() });
  const token = store.parkTokens[pet.id] ?? randomBytes(16).toString("hex");
  if (store.parkTokens[pet.id] && b?.token !== token) throw new HttpError(403, "that park id belongs to another pet");
  store.parkTokens[pet.id] = token;
  store.park[pet.id] = { pet, seen: Date.now() };
  save();
  return { id: pet.id, token };
}
function leavePark(id: string, token: string | null) {
  if (store.parkTokens[id] !== token) throw new HttpError(403, "wrong token");
  delete store.park[id];
  save();
  return { ok: true };
}
const visitHits = new Map<string, number[]>();
function sendVisit(req: IncomingMessage, b: Body) {
  if (!allow(visitHits, clientIp(req), Date.now(), 20, 3_600_000)) throw new HttpError(429, "slow down");
  const to = String(b?.to ?? "");
  if (!store.park[to]) throw new HttpError(404, "that pet isn't in the park");
  const { id: _, tricks: __, ...from } = parkPet({ ...(typeof b?.from === "object" && b.from ? (b.from as Body) : {}), id: newParkId() });
  store.visits = [...store.visits.filter((v) => Date.now() - v.at < VISIT_TTL_MS), { to, from, at: Date.now() }].slice(-5000);
  save();
  return { ok: true };
}
function takeVisits(id: string | null, token: string | null) {
  if (!id || store.parkTokens[id] !== token) throw new HttpError(403, "wrong token");
  const mine = store.visits.filter((v) => v.to === id);
  store.visits = store.visits.filter((v) => v.to !== id);
  if (mine.length) save();
  return { visits: mine.map((v) => ({ ...v.from, at: v.at })) };
}

/** The park and visit routes, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname, searchParams }: Url): Promise<Loose> {
  const m = req.method;
  if (m === "GET" && pathname === "/park") return { pets: parkList(store.park, Date.now()) };
  if (m === "POST" && pathname === "/park") return joinPark(req, await readBody(req));
  const leave = pathname.match(/^\/park\/([a-f0-9]{16,32})$/);
  if (m === "DELETE" && leave) return leavePark(leave[1], searchParams.get("token"));
  if (m === "POST" && pathname === "/visits") return sendVisit(req, await readBody(req));
  // taking visits deletes them, so it is a POST; the GET form stays one release for Macs installed before this
  if (m === "POST" && pathname === "/visits/take") {
    const b = await readBody(req);
    return takeVisits(str(b?.id, 64) ?? null, str(b?.token, 128) ?? null);
  }
  if (m === "GET" && pathname === "/visits") return takeVisits(searchParams.get("id"), searchParams.get("token"));
  return NOT_HANDLED;
}

export function housekeeping(now: number) {
  pruneHits(parkHits, now, 86_400_000);
  pruneHits(visitHits, now, 86_400_000);
}
