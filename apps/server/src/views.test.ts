import { test } from "node:test";
import assert from "node:assert/strict";
import { campaignView, CAPPED, computeMood, EMPTY, petView } from "./views.ts";

const fees = { smart: 500n, cheap: 100n };
const c = (budget: bigint, chargedToday = 0n, dailyCap = 2000n) => ({ budget, chargedToday, dailyCap });

test("campaign shape the Mac app decodes", () => {
  const v = campaignView(
    { id: 1n, brand: "brand.testnet", lineHash: "0xh", rate: 1000n },
    { lines: { "0xh": "Ship faster with Acme CI" }, brands: { "brand.testnet": "Acme" } },
  );
  assert.deepEqual(v, { campaignId: "1", line: "Ship faster with Acme CI", hooks: ["Ship faster with Acme CI"], url: null, brand: "Acme", ratePerImpression: "1000" });
});

test("a hook set is split for rotation and carries the campaign URL", () => {
  const v = campaignView(
    { id: 7n, brand: "brand.testnet", lineHash: "0xh", rate: 1000n },
    { lines: { "0xh": "Hook one\nHook two\nHook three" }, brands: {}, urls: { "7": "https://acme.dev/" } },
  );
  assert.deepEqual(v.hooks, ["Hook one", "Hook two", "Hook three"]);
  assert.equal(v.line, "Hook one");
  assert.equal(v.url, "https://acme.dev/");
  assert.equal(v.brand, "brand.testnet"); // no display name saved: the account, never a made-up name
});

test("mood and fee from the compute budget, inclusive at each fee", () => {
  assert.deepEqual(computeMood(c(500n), fees), { mood: "thriving", reason: null, fee: 500n });
  assert.deepEqual(computeMood(c(499n), fees), { mood: "stable", reason: null, fee: 100n });
  assert.deepEqual(computeMood(c(100n), fees), { mood: "stable", reason: null, fee: 100n });
  assert.deepEqual(computeMood(c(99n), fees), { mood: "hungry", reason: EMPTY, fee: null });
  assert.deepEqual(computeMood(c(0n), fees), { mood: "hungry", reason: EMPTY, fee: null });
});

test("the daily cap and in-flight charges count against the budget", () => {
  assert.equal(computeMood(c(10_000n, 1_600n), fees).mood, "stable"); // 400 left today
  assert.deepEqual(computeMood(c(10_000n, 1_950n), fees), { mood: "hungry", reason: CAPPED, fee: null });
  assert.equal(computeMood(c(600n), fees, 200n).mood, "stable"); // a 200 charge still landing
  assert.deepEqual(computeMood(null, fees), { mood: "asleep", reason: "can't read the chain", fee: null });
});

test("pet shape: earnings and compute budget come straight from the chain, never invented", () => {
  const v = petView({ name: "mochi", walletBalance: 1250000n, compute: c(0n), fees, impressionsToday: 42, seeded: false });
  assert.deepEqual(Object.keys(v), ["name", "mood", "moodReason", "walletBalance", "computeBalance", "impressionsToday", "lastThoughts", "seeded"]);
  assert.equal(v.mood, "hungry");
  assert.equal(v.moodReason, "sleeping: compute budget empty");
  assert.equal(v.walletBalance, "1250000");
  assert.equal(v.computeBalance, "0");
  const dark = petView({ name: "m", walletBalance: null, compute: null, fees, impressionsToday: 0, seeded: false });
  assert.deepEqual([dark.mood, dark.walletBalance, dark.computeBalance], ["asleep", null, null]);
});
