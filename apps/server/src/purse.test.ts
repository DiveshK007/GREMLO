import { test } from "node:test";
import assert from "node:assert/strict";
import { overdue, owed, paymentMatches, purseFits, RESERVE, spendable } from "./purse.ts";

const want = { purse: "mochi.gremlo.testnet", provider: "operator.gremlo.testnet", amount: "500000000000000000000", requestId: "chatcmpl-abc" };
const event = (o: object = {}) => `EVENT_JSON:${JSON.stringify({ standard: "gremlo", version: "1.0.0", event: "paid_for_thinking", data: { provider: want.provider, amount: want.amount, request_id: want.requestId, ...o } })}`;
const outcome = (o: { signer?: string; logs?: string[]; fail?: boolean } = {}) => ({
  status: o.fail ? { Failure: { ActionError: {} } } : { SuccessValue: "" },
  transaction: { signer_id: o.signer ?? want.purse, receiver_id: want.purse },
  receipts_outcome: [{ outcome: { logs: o.logs ?? [event()], status: { SuccessReceiptId: "x" } } }, { outcome: { logs: [], status: { SuccessValue: "" } } }],
});

test("a payment counts only when the purse itself paid exactly this thought", () => {
  assert.ok(paymentMatches(outcome(), want));
  assert.ok(!paymentMatches(outcome({ signer: "someone.testnet" }), want), "signed by the purse's own key");
  assert.ok(!paymentMatches(outcome({ fail: true }), want), "a failed tx pays nothing");
  assert.ok(!paymentMatches(outcome({ logs: [event({ amount: "1" })] }), want), "the full fee, not less");
  assert.ok(!paymentMatches(outcome({ logs: [event({ request_id: "other" })] }), want), "this thought, not another");
  assert.ok(!paymentMatches(outcome({ logs: [event({ provider: "me.testnet" })] }), want), "to this operator");
  assert.ok(!paymentMatches(outcome({ logs: ["paid"] }), want));
});

test("spendable keeps the storage stake and the reserve; owed and overdue drive the budget check", () => {
  assert.equal(spendable(RESERVE + 1000n * 10n ** 19n + 7n, 1000), 7n);
  assert.equal(spendable(1n, 1000), 0n);
  assert.ok(purseFits({ owner: "o", providers: ["op"], per_call: "1", daily: "2", spent_today: "0", total_paid: "0" }, "o", "op"));
  assert.ok(!purseFits({ owner: "x", providers: ["op"], per_call: "1", daily: "2", spent_today: "0", total_paid: "0" }, "o", "op"));
  assert.ok(!purseFits(null, "o", "op"));
  const now = 1_000_000_000_000;
  const list = [
    { action: "hold", requestId: "a", at: now / 1000 - 60, due: "5" },
    { action: "hold", requestId: "b", at: now / 1000 - 3600, due: "7" },
    { action: "hold", requestId: "c", at: now / 1000 - 7200, due: "9", chargeTx: "paid" },
  ];
  assert.equal(owed(list), 12n);
  assert.equal(overdue(list, now)?.requestId, "b", "the oldest unpaid past the grace period");
  assert.equal(overdue(list.slice(0, 1), now), null, "a minute old is still within grace");
});
