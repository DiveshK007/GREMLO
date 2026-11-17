// Community species: submit, report, review and list.

import { type IncomingMessage } from "node:http";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { allow } from "../batch.ts";
import { bad, HttpError } from "../register.ts";
import { capSet, pruneHits } from "../prune.ts";
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { checkSubmission, report as reportSpecies } from "../gallery.ts";
import { type Body, type Loose } from "../json.ts";
import { NOT_HANDLED, type Url, clientIp, parse, readBody, readRaw, save, store } from "../state.ts";

const GALLERY_DIR = process.env.GALLERY_DIR ?? new URL("../gallery", import.meta.url).pathname;
const galleryHits = new Map<string, number[]>();
function submitSpecies(req: IncomingMessage, raw: string) {
  if (!allow(galleryHits, clientIp(req), Date.now(), 5, 86_400_000)) throw new HttpError(429, "5 submissions a day");
  const b = parse(raw);
  const name = String(b?.name ?? "").trim(),
    creator = String(b?.creator ?? "").trim();
  if (!/^[a-z0-9-]{2,24}$/.test(name)) throw bad("name is 2-24 of a-z, 0-9, -");
  if (!creator || creator.length > 40) throw bad("creator is 1-40 characters (shown as credit)");
  if (b?.ownArt !== true) throw bad("confirm you made the art (Codex imports stay local)");
  const { rows } = checkSubmission(b?.files ?? {});
  const id = randomBytes(6).toString("hex");
  mkdirSync(`${GALLERY_DIR}/${id}`, { recursive: true });
  for (const [f, data] of Object.entries(b.files as Record<string, string>)) writeFileSync(`${GALLERY_DIR}/${id}/${f}`, Buffer.from(data, "base64"));
  store.gallery.push({ id, name, creator, status: "review", reports: 0, at: Date.now(), rows });
  save();
  console.log(`gallery: ${name} by ${creator} submitted for review (${id})`);
  return { id, status: "review", note: "Two reviewers play every row; target two working days. Machines check format, image safety, look-alikes and text first." };
}
const galleryReports = new Set<string>(); // species id + visitor: one report each
function reportGallery(req: IncomingMessage, id: string) {
  const s = store.gallery.find((x) => x.id === id);
  if (!s) throw new HttpError(404, "unknown species");
  const ip = clientIp(req),
    key = `${id}:${createHash("sha256").update(ip).digest("hex").slice(0, 12)}`;
  if (!allow(galleryHits, `report:${ip}`, Date.now(), 10, 3_600_000)) throw new HttpError(429, "slow down");
  if (galleryReports.has(key)) return { status: s.status };
  galleryReports.add(key);
  reportSpecies(s);
  save();
  return { status: s.status };
}
/** A reviewer (GALLERY_REVIEW_TOKEN) who played every row approves; two different reviewers list it. */
function reviewGallery(req: IncomingMessage, id: string, b: Body) {
  const token = process.env.GALLERY_REVIEW_TOKEN ?? "",
    got = String(req.headers["x-review-token"] ?? "");
  if (!token || got.length !== token.length || !timingSafeEqual(Buffer.from(got), Buffer.from(token))) throw new HttpError(403, "reviewers only");
  const s = store.gallery.find((x) => x.id === id);
  if (!s) throw new HttpError(404, "unknown species");
  const who = String(b?.reviewer ?? "").trim();
  if (!who || b?.playedEveryRow !== true) throw bad("reviewer and playedEveryRow: true");
  const list = (store.galleryReviews[id] ??= []);
  if (!list.includes(who)) list.push(who);
  if (list.length >= 2 && s.status === "review") s.status = "listed";
  save();
  return { status: s.status, reviewers: list.length };
}

/** The gallery routes, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname }: Url): Promise<Loose> {
  const m = req.method;
  // listed and paused species (a paused one stays visible, marked, so it doesn't vanish for people who have it)
  if (m === "GET" && pathname === "/gallery")
    return { species: store.gallery.filter((s) => s.status !== "review").map((s) => ({ id: s.id, name: s.name, creator: s.creator, rows: s.rows, at: s.at, paused: s.status === "paused" })) };
  const sheet = pathname.match(/^\/gallery\/([a-f0-9]{12})\/sheet\.png$/);
  if (m === "GET" && sheet) {
    const s = store.gallery.find((x) => x.id === sheet[1] && x.status !== "review");
    if (!s || !existsSync(`${GALLERY_DIR}/${s.id}/spritesheet.png`)) throw new HttpError(404, "unknown species");
    return { file: readFileSync(`${GALLERY_DIR}/${s.id}/spritesheet.png`), type: "image/png" };
  }
  if (m === "POST" && pathname === "/gallery") return submitSpecies(req, await readRaw(req, 12_000_000));
  const g = pathname.match(/^\/gallery\/([a-f0-9]{12})\/(report|review)$/);
  if (m === "POST" && g) return g[2] === "report" ? reportGallery(req, g[1]) : reviewGallery(req, g[1], await readBody(req));
  return NOT_HANDLED;
}

export function housekeeping(now: number) {
  pruneHits(galleryHits, now, 86_400_000);
  capSet(galleryReports, 50_000);
}
