import { createReadStream, existsSync } from "node:fs";
import { once } from "node:events";
import { createInterface } from "node:readline";
import type { Writable } from "node:stream";

/**
 * Writes `{...head, "entries": [...]}` for a campaign's append-only .jsonl log without loading the file: one line at
 * a time, with backpressure, so a long log neither blocks the server nor sits in memory. `after` tails: only entries
 * with index > after (a verifier that already holds the earlier ones asks for the rest). Same JSON shape as before.
 */
export async function streamLog(out: Writable, file: string, head: object, after = 0) {
  const put = async (s: string) => {
    if (!out.write(s)) await once(out, "drain");
  };
  await put(`${JSON.stringify(head).slice(0, -1)},"entries":[`);
  let first = true;
  if (existsSync(file)) {
    for await (const line of createInterface({ input: createReadStream(file, "utf8"), crlfDelay: Infinity })) {
      if (!line) continue;
      if (after > 0 && !(JSON.parse(line).i > after)) continue; // only parsed when tailing
      await put((first ? "" : ",") + line);
      first = false;
    }
  }
  out.end("]}");
}
