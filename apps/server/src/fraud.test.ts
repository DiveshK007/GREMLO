import { test } from "node:test";
import assert from "node:assert/strict";
import { hold, review } from "./fraud.ts";

test("holdback: views wait their hours, then pay", () => {
  const held = hold(hold([], "0xa", 100, "ip1"), "0xa", 100, "ip1");
  assert.deepEqual(held, [{ pet: "0xa", hour: 100, ip: "ip1", n: 2 }]);
  assert.equal(review(held, 110, 24).waiting.length, 1);
  assert.deepEqual(review(held, 124, 24).ok, held);
  assert.deepEqual(review(held, 100, 0).ok, held); // holdback off: due at once
});

test("fraud: a farm behind one network is voided, a household isn't", () => {
  let held = ["0xa", "0xb", "0xc"].reduce((h, p) => hold(h, p, 5, "home"), [] as ReturnType<typeof hold>);
  assert.equal(review(held, 5, 0).voided.length, 0);
  held = ["0xa", "0xb", "0xc", "0xd"].reduce((h, p) => hold(h, p, 5, "farm"), [] as ReturnType<typeof hold>);
  const r = review(held, 5, 0);
  assert.equal(r.ok.length, 0);
  assert.equal(r.voided[0].reason, "too many pets from one network in an hour");
});

test("fraud: a pet seen in more than 20 hours of one day is voided", () => {
  let held: ReturnType<typeof hold> = [];
  for (let h = 0; h < 21; h++) held = hold(held, "0xbot", 24 * 10 + h, "x");
  assert.equal(review(held, 24 * 11, 0).voided.length, 21);
  held = held.slice(0, 20);
  assert.equal(review(held, 24 * 11, 0).voided.length, 0);
});
