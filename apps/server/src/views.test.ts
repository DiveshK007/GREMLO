import { test } from "node:test";
import assert from "node:assert/strict";
import { campaignView, moodFor, petView } from "./views.ts";

const t = { thriving: 1000n, stable: 100n, hungry: 10n };

test("campaign shape the Mac app decodes", () => {
  const v = campaignView(
    { id: 1n, brand: "0xB", lineHash: "0xh", rate: 1000n },
    { lines: { "0xh": "Ship faster with Acme CI" }, brands: { "0xB": "Acme" } },
  );
  assert.deepEqual(v, { campaignId: "1", line: "Ship faster with Acme CI", brand: "Acme", ratePerImpression: "1000" });
});

test("mood thresholds, inclusive at each boundary", () => {
  assert.equal(moodFor(1000n, t), "thriving");
  assert.equal(moodFor(999n, t), "stable");
  assert.equal(moodFor(100n, t), "stable");
  assert.equal(moodFor(99n, t), "hungry");
  assert.equal(moodFor(10n, t), "hungry");
  assert.equal(moodFor(9n, t), "asleep");
  assert.equal(moodFor(0n, t), "asleep");
});

test("pet shape never invents a meal or a compute balance", () => {
  const v = petView({ name: "mochi.notchi.eth", walletBalance: 1250000n, thresholds: t, impressionsToday: 42, seeded: true });
  assert.deepEqual(Object.keys(v), [
    "name", "mood", "moodReason", "walletBalance", "computeBalance", "impressionsToday", "lastThoughts", "lastMeal", "seeded",
  ]);
  assert.equal(v.mood, "thriving");
  assert.equal(v.moodReason, null);
  assert.equal(v.walletBalance, "1250000");
  assert.equal(v.computeBalance, null);
  assert.equal(v.lastMeal, null);
});

test("unreadable balance means asleep with a reason", () => {
  const v = petView({ name: "m", walletBalance: null, thresholds: t, impressionsToday: 0, seeded: true });
  assert.equal(v.mood, "asleep");
  assert.equal(v.moodReason, "can't read balance");
  assert.equal(v.walletBalance, null);
});
