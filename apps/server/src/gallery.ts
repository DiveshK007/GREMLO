// R2 §13: community species. Submissions are checked here, then two people review them before the gallery
// lists them. Only reviewed species can be earners. Nothing is sold; creators get credit.

import { HttpError } from "./register.ts";
const bad = (m: string) => new HttpError(400, m);

/** Width and height from a PNG's IHDR chunk, or null if it isn't a PNG. */
export function pngSize(b: Buffer): { w: number; h: number } | null {
  if (b.length < 24 || b.readUInt32BE(0) !== 0x89504e47 || b.toString("ascii", 12, 16) !== "IHDR") return null;
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

export type Submission = { id: string; name: string; creator: string; status: "review" | "listed" | "paused"; reports: number; at: number; rows: number };
export const MAX_BYTES = 8 * 1024 * 1024;

/** pet.json parses with the spec's fields and the sheet's size matches its rows and cells. */
export function checkSubmission(files: Record<string, string>) {
  const json = files["pet.json"], sheet = files["spritesheet.png"];
  if (!json || !sheet) throw bad("pet.json and spritesheet.png are required");
  const total = Object.values(files).reduce((n, f) => n + Buffer.byteLength(f, "base64"), 0);
  if (total > MAX_BYTES) throw bad("a pack is at most 8 MB");
  let meta: any;
  try { meta = JSON.parse(Buffer.from(json, "base64").toString("utf8")).gremlo; } catch { throw bad("pet.json doesn't parse"); }
  if (!meta?.rows || !Array.isArray(meta.cell) || !meta.columns) throw bad("pet.json needs gremlo.rows, cell and columns");
  const rows = Object.keys(meta.rows).length;
  const size = pngSize(Buffer.from(sheet, "base64"));
  if (!size) throw bad("spritesheet.png isn't a PNG");
  if (size.w !== meta.columns * meta.cell[0] || size.h !== rows * meta.cell[1]) throw bad(`spritesheet is ${size.w}x${size.h}; ${rows} rows need ${meta.columns * meta.cell[0]}x${rows * meta.cell[1]}`);
  for (const k of Object.keys(files)) if (!["pet.json", "spritesheet.png", "signkit.png", "accessories.png"].includes(k)) throw bad(`unexpected file ${k}`);
  return { rows };
}

/** Three reports pause new hatches of a species while it's re-checked; pets already hatched keep working. */
export const report = (s: Submission) => { s.reports++; if (s.reports >= 3 && s.status === "listed") s.status = "paused"; return s; };
