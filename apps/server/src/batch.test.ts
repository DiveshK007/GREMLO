import { test } from "node:test";
import assert from "node:assert/strict";
import { planSettlement } from "./batch.ts";

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
