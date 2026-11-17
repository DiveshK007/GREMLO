import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Writable } from "node:stream";
import { appendFileSync } from "node:fs";
import { capSet, pruneHits, pruneStamps } from "./prune.ts";
import { makeSaver } from "./saver.ts";
import { streamLog } from "./logstream.ts";
import { makeDailyCap } from "./batch.ts";

test("prune: old rate-limit keys and stamps go, fresh ones stay; a set keeps its newest entries", () => {
  const hits = new Map([["old", [1_000]], ["fresh", [9_500]], ["empty", []]]);
  pruneHits(hits, 10_000, 5_000);
  assert.deepEqual([...hits.keys()], ["fresh"]);
  const stamps = new Map([["a", 1_000], ["b", 9_000]]);
  pruneStamps(stamps, 10_000, 5_000);
  assert.deepEqual([...stamps.keys()], ["b"]);
  const s = new Set(["1", "2", "3", "4"]);
  capSet(s, 2);
  assert.deepEqual([...s], ["3", "4"]);
});

test("saver: a burst is one write, saveNow is immediate, flush writes what is pending, no temp file is left", async () => {
  const dir = mkdtempSync(join(tmpdir(), "gremlo-save-"));
  const file = join(dir, "data.json");
  let writes = 0, state = { n: 0 };
  const saver = makeSaver(file, () => { writes++; return state; }, 20);
  state.n = 1; saver.save(); state.n = 2; saver.save(); state.n = 3; saver.save();
  assert.equal(existsSync(file), false); // nothing yet
  await new Promise((r) => setTimeout(r, 60));
  assert.equal(writes, 1);
  assert.deepEqual(JSON.parse(readFileSync(file, "utf8")), { n: 3 });
  state.n = 4; saver.saveNow();
  assert.deepEqual(JSON.parse(readFileSync(file, "utf8")), { n: 4 });
  state.n = 5; saver.save(); saver.flush();
  assert.deepEqual(JSON.parse(readFileSync(file, "utf8")), { n: 5 });
  assert.equal(existsSync(`${file}.tmp`), false);
});

test("log stream: valid JSON with every entry, a tail from an index, and an empty log", async () => {
  const dir = mkdtempSync(join(tmpdir(), "gremlo-log-"));
  const file = join(dir, "campaign-1.jsonl");
  for (let i = 1; i <= 5; i++) appendFileSync(file, JSON.stringify({ i, hash: `h${i}`, counts: [i] }) + "\n");
  const run = async (f: string, after?: number) => {
    let out = "";
    await streamLog(new Writable({ write(c, _e, cb) { out += c; cb(); } }), f, { campaign: "1", billed: { settled: 2 } }, after);
    return JSON.parse(out);
  };
  const all = await run(file);
  assert.deepEqual(all.entries.map((e: any) => e.i), [1, 2, 3, 4, 5]);
  assert.deepEqual(all.billed, { settled: 2 });
  assert.deepEqual((await run(file, 3)).entries.map((e: any) => e.i), [4, 5]);
  assert.deepEqual((await run(join(dir, "none.jsonl"))).entries, []);
});

test("daily cap: a failed call gives its slot back, and a new day starts fresh", () => {
  const c = makeDailyCap(2);
  assert.deepEqual([c.take("d1"), c.take("d1"), c.take("d1")], [true, true, false]);
  c.refund("d1");
  assert.equal(c.take("d1"), true);
  assert.equal(c.take("d2"), true);
  c.refund("d1"); // a refund for yesterday must not touch today
  assert.deepEqual([c.take("d2"), c.take("d2")], [true, false]);
});
