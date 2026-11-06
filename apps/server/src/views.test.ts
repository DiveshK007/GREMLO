import { test } from "node:test";
import assert from "node:assert/strict";
import { campaignView, petView } from "./views.ts";

test("campaign shape the Mac app decodes", () => {
  const v = campaignView(
    { id: 1n, brand: "0xB", lineHash: "0xh", rate: 1000n },
    { lines: { "0xh": "Ship faster with Acme CI" }, brands: { "0xB": "Acme" } },
  );
  assert.deepEqual(v, { campaignId: "1", line: "Ship faster with Acme CI", brand: "Acme", ratePerImpression: "1000" });
});

test("pet shape never invents a meal or a compute balance", () => {
  const v = petView({ name: "mochi.notchi.eth", walletBalance: 1250000n, impressionsToday: 42, seeded: true });
  assert.deepEqual(Object.keys(v), [
    "name", "mood", "walletBalance", "computeBalance", "impressionsToday", "lastThoughts", "lastMeal", "seeded",
  ]);
  assert.equal(v.walletBalance, "1250000");
  assert.equal(v.computeBalance, null);
  assert.equal(v.lastMeal, null);
});
