// POST /diagnostics: one opt-in report from a Mac, appended to diagnostics.jsonl in LOG_DIR. Unsigned on purpose,
// so it can't be tied to a pet or a device; rate-limited per address, and the address is never written down.

import { type IncomingMessage } from "node:http";
import { appendFileSync } from "node:fs";
import { allow } from "../batch.ts";
import { HttpError } from "../register.ts";
import { pruneHits } from "../prune.ts";
import { cleanDiagnostics } from "../diagnostics.ts";
import { type Loose } from "../json.ts";
import { NOT_HANDLED, type Url, clientIp, diagnosticsFile, readBody } from "../state.ts";

const hits = new Map<string, number[]>();

/** The diagnostics route, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname }: Url): Promise<Loose> {
  if (req.method !== "POST" || pathname !== "/diagnostics") return NOT_HANDLED;
  if (!allow(hits, clientIp(req), Date.now(), 6, 3_600_000)) throw new HttpError(429, "Too many diagnostics reports from this address. Try again in an hour.");
  const report = cleanDiagnostics(await readBody(req));
  appendFileSync(diagnosticsFile, JSON.stringify({ at: Math.floor(Date.now() / 3_600_000) * 3_600_000, ...report }) + "\n"); // the hour is enough
  return { ok: true };
}

export function housekeeping(now: number) {
  pruneHits(hits, now, 86_400_000);
}
