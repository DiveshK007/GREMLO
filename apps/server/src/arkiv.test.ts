import { test } from "node:test";
import assert from "node:assert/strict";
import { arkivOn, cardExpiry, receiptExpiry } from "./arkiv.ts";

test("Arkiv data expires with the campaign: cards a week after the settle window, receipts a month after the end", () => {
  const end = 1_800_000_000n;
  assert.equal(cardExpiry(end).getTime(), (1_800_000_000 + 3600 + 7 * 86400) * 1000);
  assert.equal(receiptExpiry(end).getTime(), (1_800_000_000 + 30 * 86400) * 1000);
});

test("Arkiv stays off without its keys, so nothing is published by accident", () => {
  if (!process.env.ARKIV_ACCESS_KEY || !process.env.ARKIV_KEY) assert.equal(arkivOn, false);
});
