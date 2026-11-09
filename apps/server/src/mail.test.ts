import { test } from "node:test";
import assert from "node:assert/strict";
import { alertDue, bestHook, checkEmail, sumSince, usedPct, weeklyReport } from "./mail.ts";

test("budget alerts: each level once, highest reached wins, integer percent", () => {
  assert.equal(usedPct(49n, 100n), 49);
  assert.equal(usedPct(1n, 3n), 33); // rounds down
  assert.equal(usedPct(5n, 0n), 0);
  assert.equal(alertDue(49, 0), 0);
  assert.equal(alertDue(50, 0), 50);
  assert.equal(alertDue(79, 50), 0); // already sent 50
  assert.equal(alertDue(85, 0), 80); // jumped past 50: send only the higher one
  assert.equal(alertDue(100, 80), 100);
  assert.equal(alertDue(100, 100), 0);
});

test("best hook needs 20 views; ties keep the first", () => {
  assert.equal(bestHook([10, 5], [5, 5]), null);
  assert.equal(bestHook([100, 40, 19], [2, 2, 19]), 1);
  assert.equal(bestHook([20, 20], [1, 1]), 0);
});

test("brand email is optional and checked", () => {
  assert.equal(checkEmail(""), undefined);
  assert.equal(checkEmail(" a@b.co "), "a@b.co");
  assert.throws(() => checkEmail("a@b"));
  assert.throws(() => checkEmail("a@b.co, c@d.co"));
});

test("weekly sums and report use only real numbers", () => {
  const p = [
    { at: 0, id: "1", pet: "0xa", views: 3, wei: "30" },
    { at: 10, id: "1", pet: "0xb", views: 2, wei: "20" },
    { at: 10, id: "2", pet: "0xa", views: 9, wei: "90" },
  ];
  assert.deepEqual(sumSince(p, 5, (x) => x.pet === "0xa"), { views: 9, wei: 90n });
  const r = weeklyReport({ id: "1", hooks: ["a", "b"], views: [30, 0], clicks: [3, 0], spent: 5n * 10n ** 17n, budget: 10n ** 18n, humans: 1, link: "x" });
  assert.match(r, /30 views from 1 verified human, 3 clicks/);
  assert.match(r, /Spent 0\.5 of 1 0G \(50%\)/);
  assert.match(r, /Best hook: "a" \(10\.0% click rate\)/);
});
