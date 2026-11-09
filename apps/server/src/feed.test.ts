import { test } from "node:test";
import assert from "node:assert/strict";
import { parseEther } from "viem";
import { costWei, planFeed, RESERVE_WEI } from "./feed.ts";

const e = (s: string) => parseEther(s);
const base = { fedToday: 0n, cap: e("0.05"), approved: 0n, credit: e("1") };

test("feeding: keeps the gas reserve, respects the daily cap, skips dust", () => {
  assert.deepEqual(planFeed({ ...base, balance: e("0.02") }), { deposit: e("0.02") - RESERVE_WEI, ask: 0n });
  assert.equal(planFeed({ ...base, balance: RESERVE_WEI }).deposit, 0n); // nothing above the reserve
  assert.equal(planFeed({ ...base, balance: RESERVE_WEI + e("0.0005") }).deposit, 0n); // dust waits
  assert.equal(planFeed({ ...base, balance: e("1") }).deposit, e("0.05")); // capped
  assert.equal(planFeed({ ...base, balance: e("1"), fedToday: e("0.04") }).deposit, e("0.01")); // what's left today
  assert.equal(planFeed({ ...base, balance: e("1"), fedToday: e("0.06") }).deposit, 0n); // over cap never goes negative
});

test("above the cap: ask the owner only when the pet runs low; an approval raises today's room", () => {
  const capped = { ...base, balance: e("1"), fedToday: e("0.05") };
  assert.equal(planFeed(capped).ask, 0n); // plenty of credit: no nagging
  const hungry = planFeed({ ...capped, credit: 0n });
  assert.equal(hungry.deposit, 0n);
  assert.equal(hungry.ask, e("1") - RESERVE_WEI);
  assert.equal(planFeed({ ...capped, credit: 0n, approved: e("0.3") }).deposit, e("0.3"));
});

test("router cost: neuron integers, 0G decimals, nothing invented", () => {
  assert.equal(costWei("1250000000000"), 1250000000000n);
  assert.equal(costWei(42), 42n);
  assert.equal(costWei("0.000003"), 3000000000000n);
  assert.equal(costWei(null), null);
  assert.equal(costWei("-1"), null);
  assert.equal(costWei("abc"), null);
});
