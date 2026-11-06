import { test } from "node:test";
import assert from "node:assert/strict";
import { countImpression, markSettled, planSettlement } from "./batch.ts";

test("settles everything when the budget covers it", () => {
  const r = planSettlement({ "0xb": 3, "0xa": 2 }, 10n, 1000n);
  assert.deepEqual(r.settle, [
    { pet: "0xa", count: 2, amount: 20n },
    { pet: "0xb", count: 3, amount: 30n },
  ]);
  assert.deepEqual(r.leftover, {});
});

test("never pays more than remaining; the rest stays pending", () => {
  // 75 wei left at 10 wei each pays 7 impressions; 5 wei of dust is not spent
  const r = planSettlement({ "0xa": 4, "0xb": 5, "0xc": 2 }, 10n, 75n);
  assert.deepEqual(r.settle, [
    { pet: "0xa", count: 4, amount: 40n },
    { pet: "0xb", count: 3, amount: 30n },
  ]);
  assert.deepEqual(r.leftover, { "0xb": 2, "0xc": 2 });
  const total = r.settle.reduce((s, x) => s + x.amount, 0n);
  assert.ok(total <= 75n);
});

test("empty budget settles nothing", () => {
  const r = planSettlement({ "0xa": 1 }, 10n, 9n);
  assert.deepEqual(r.settle, []);
  assert.deepEqual(r.leftover, { "0xa": 1 });
});

test("an impression counts once per pet per campaign per window", () => {
  const last: Record<string, number> = {};
  assert.equal(countImpression(last, "1:0xa", 0, 60_000), true);
  assert.equal(countImpression(last, "1:0xa", 59_999, 60_000), false);
  assert.equal(countImpression(last, "2:0xa", 59_999, 60_000), true); // other campaign
  assert.equal(countImpression(last, "1:0xa", 60_000, 60_000), true);
});

test("a sent but unconfirmed settle is never paid again; a failed one stays pending", () => {
  const p = { "0xa": 5, "0xb": 2 };
  markSettled(p, "0xa", 3, "unconfirmed");
  markSettled(p, "0xb", 2, "failed");
  assert.deepEqual(p, { "0xa": 2, "0xb": 2 });
  markSettled(p, "0xa", 2, "paid");
  assert.deepEqual(p, { "0xb": 2 });
});
