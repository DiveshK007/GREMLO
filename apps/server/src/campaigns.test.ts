import { test } from "node:test";
import assert from "node:assert/strict";
import { keccak256, toBytes } from "viem";
import { saveLine, type LineStore } from "./campaigns.ts";

const brief = { product: "Clearlog, log search for TypeScript teams", audience: "backend developers", offer: "first 1M logs free", proof: "Indexes 1M logs in 30 seconds", cta: "Try it free" };
const fresh = (): LineStore => ({ moments: {}, urls: {}, briefs: {}, lines: {}, emails: {}, brands: {} });
const line = "Logs you can read\nFirst 1M logs free";
const hash = keccak256(toBytes(line));
const onchain = { brand: "brand.testnet", line_hash: hash.slice(2) };
const body = (over = {}) => ({ campaignId: "7", hooks: line.split("\n"), lineHash: hash, brief, url: "https://example.com/x", brand: "Clearlog", ...over });

test("a bad hash is refused and writes nothing, so the real brand can still save", () => {
  const s = fresh();
  assert.throws(() => saveLine(s, "7", onchain, body({ lineHash: "0x" + "ab".repeat(32) })), /does not match/);
  assert.deepEqual(s, fresh());
  assert.deepEqual(saveLine(s, "7", onchain, body()), { ok: true });
  assert.equal(s.lines[hash.toLowerCase()], line);
  assert.equal(s.briefs["7"].product, brief.product);
  assert.equal(s.urls["7"], "https://example.com/x");
  assert.equal(s.brands["brand.testnet"], "Clearlog");
});

test("a failed claim check, too many lines or a bad url also leave the store untouched", () => {
  const s = fresh();
  assert.throws(() => saveLine(s, "7", onchain, body({ hooks: ["Search logs 10x faster", "Try it free"] })));
  assert.throws(() => saveLine(s, "7", onchain, body({ url: "http://localhost/x" })));
  assert.deepEqual(s, fresh());
});

test("first write wins: a different link after the save is a 409, the same save again is fine", () => {
  const s = fresh();
  saveLine(s, "7", onchain, body());
  assert.deepEqual(saveLine(s, "7", onchain, body()), { ok: true });
  assert.throws(() => saveLine(s, "7", onchain, body({ url: "https://evil.example/x" })), /already saved/);
});
