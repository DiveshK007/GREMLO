import { test } from "node:test";
import assert from "node:assert/strict";
import { clearDraft, keepDraft, loadDraft, type Draft } from "./draft.ts";
import { plainError } from "./errors.ts";

const mem = () => {
  const m = new Map<string, string>();
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => void m.set(k, v), removeItem: (k: string) => void m.delete(k) };
};
const d: Draft = {
  campaignId: "7",
  hooks: ["a line", "another"],
  moments: ["any", "any"],
  lineHash: "0x" + "ab".repeat(32),
  brand: "b.testnet",
  txHash: "Tx1",
  url: "https://x.example",
  brief: { product: "p", audience: "a", offer: "", proof: "", cta: "c" },
};

test("a draft survives a reload and is gone once cleared", () => {
  const s = mem();
  assert.equal(loadDraft(s), null);
  keepDraft(d, s);
  assert.deepEqual(loadDraft(s), d);
  clearDraft(s);
  assert.equal(loadDraft(s), null);
});

test("storage that is missing or broken never throws", () => {
  assert.doesNotThrow(() => keepDraft(d, null));
  assert.equal(loadDraft(null), null);
  assert.equal(loadDraft({ getItem: () => "{not json", setItem() {}, removeItem() {} }), null);
  assert.equal(loadDraft({ getItem: () => JSON.stringify({ campaignId: 7 }), setItem() {}, removeItem() {} }), null);
});

test("plainError: wallet cancels and code noise become sentences, our messages pass through", () => {
  assert.match(plainError(new Error("User rejected the request")), /closed the wallet/);
  assert.match(plainError(new TypeError("Cannot read properties of undefined (reading 'x')")), /went wrong on our side/);
  assert.equal(plainError(new Error("Campaign #3 was just settled. Try again in 40 seconds.")), "Campaign #3 was just settled. Try again in 40 seconds.");
});
