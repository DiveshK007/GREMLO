import { test } from "node:test";
import assert from "node:assert/strict";
import { review } from "./fraud.ts";
import { allow, countImpression, hookOrder, level, markDay, markSettled, planSettlement, streak, underDailyCap, workFor } from "./batch.ts";

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

test("auto-optimise: clicked hooks get more slots, young hooks keep a floor", () => {
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  // hook 1 converts at 10%, hooks 0 and 2 at 1%, all past the exploration phase
  const order = hookOrder([1000, 1000, 1000], [10, 100, 10], 3, rand, 600);
  const share = (i: number) => order.filter((x) => x === i).length / order.length;
  assert.ok(share(1) > 0.9, `best hook share ${share(1)}`);
  // a new hook with no views still gets roughly the floor while it explores
  const withNew = hookOrder([1000, 1000, 0], [10, 100, 0], 3, rand, 2000);
  const newShare = withNew.filter((x) => x === 2).length / withNew.length;
  assert.ok(newShare >= 0.12 && newShare < 0.5, `new hook share ${newShare}`);
  // every slot is a valid hook index
  assert.ok(hookOrder([], [], 4, rand).every((i) => i >= 0 && i < 4));
});

test("rate limit: N per window per key, then it frees up", () => {
  const hits = new Map<string, number[]>();
  const hour = 3_600_000;
  assert.deepEqual([0, 1, 2, 3].map((i) => allow(hits, "ip-a", i * 1000, 3, hour)), [true, true, true, false]);
  assert.equal(allow(hits, "ip-b", 4000, 3, hour), true); // other keys are separate
  assert.equal(allow(hits, "ip-a", hour + 1, 3, hour), true); // the first hit aged out
});

test("worker: settle while the contract pays, refund once the grace is over, never touch closed campaigns", () => {
  const c = { closed: false, endTime: 1000n, remaining: 50n };
  assert.equal(workFor(c, 3, 900n), "settle"); // running
  assert.equal(workFor(c, 3, 1000n + 3600n), "settle"); // last second of grace
  assert.equal(workFor(c, 0, 900n), "none"); // nothing queued
  assert.equal(workFor(c, 3, 1000n + 3601n), "refund"); // queued views can't be paid any more
  assert.equal(workFor({ ...c, remaining: 0n }, 0, 9999n), "none"); // fully spent: nothing to refund
  assert.equal(workFor({ ...c, closed: true }, 3, 900n), "none");
});

test("daily view cap per pet", () => {
  assert.equal(underDailyCap(0), true);
  assert.equal(underDailyCap(119), true);
  assert.equal(underDailyCap(120), false);
});

test("streak: consecutive days ending today or yesterday; level from paid views", () => {
  assert.deepEqual(markDay(markDay([], "2026-11-08"), "2026-11-08"), ["2026-11-08"]);
  const days = ["2026-11-01", "2026-11-06", "2026-11-07", "2026-11-08"];
  assert.equal(streak(days, "2026-11-08"), 3);
  assert.equal(streak(days, "2026-11-09"), 3); // not coded yet today: still alive
  assert.equal(streak(days, "2026-11-10"), 0); // a missed day ends it
  assert.equal(streak(["2026-10-31", "2026-11-01"], "2026-11-01"), 2); // across a month
  assert.equal(streak([], "2026-11-01"), 0);
  assert.deepEqual([0, 9, 10, 39, 40, 90].map(level), [1, 1, 2, 2, 3, 4]);
});

test("the worker settles before it closes: views held back are released at the end and paid inside the grace hour", () => {
  const c = { closed: false, endTime: 1000n, remaining: 500n };
  // 4 views still in a 24 h holdback when the campaign ends; at the end they are reviewed with no wait
  const held = [{ pet: "mochi", hour: 0, ip: "a", n: 4 }];
  assert.equal(review(held, 0, 24).ok.length, 0, "still held while the campaign runs");
  const released = review(held, 0, 0).ok.reduce((a, h) => a + h.n, 0);
  assert.equal(released, 4);
  for (const t of [1000n, 1001n, 1000n + 3600n]) assert.equal(workFor(c, released, t), "settle", `at ${t} it pays, never closes`);
  assert.equal(workFor(c, 0, 1001n), "none", "ended but inside the grace hour with nothing queued: it waits, no early close");
  assert.equal(workFor(c, 0, 1000n + 3601n), "refund", "only after the grace hour does it close and refund");
});
