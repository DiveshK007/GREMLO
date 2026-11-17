import { test } from "node:test";
import assert from "node:assert/strict";
import { makeReserve } from "./reserve.ts";
import { cooldown } from "./batch.ts";
import { toHttp, HttpError } from "./register.ts";

test("two concurrent thoughts can't both spend a budget that covers one", async () => {
  const r = makeReserve();
  const think = async () => {
    const ok = r.tryHold("mochi", 600n, 500n); // the check and the hold are one step
    await new Promise((res) => setTimeout(res, 5)); // the slow AI call
    return ok;
  };
  const [a, b] = await Promise.all([think(), think()]);
  assert.deepEqual([a, b].sort(), [false, true]);
  assert.equal(r.held("mochi"), 500n);
});

test("a hold comes off when the call fails or is billed, and the budget is usable again", () => {
  const r = makeReserve();
  assert.equal(r.tryHold("p", 1000n, 500n), true);
  assert.equal(r.tryHold("p", 1000n, 500n), true);
  assert.equal(r.tryHold("p", 1000n, 500n), false); // 1000 held of 1000
  r.release("p", 500n);
  assert.equal(r.tryHold("p", 1000n, 500n), true);
  r.release("p", 500n);
  r.release("p", 500n);
  assert.equal(r.held("p"), 0n);
});

test("cooldown: one run per key per window", () => {
  const m = new Map<string, number>();
  assert.equal(cooldown(m, "3", 1000, 60_000), 0);
  assert.equal(cooldown(m, "3", 31_000, 60_000), 30_000);
  assert.equal(cooldown(m, "4", 31_000, 60_000), 0);
  assert.equal(cooldown(m, "3", 61_000, 60_000), 0);
});

test("errors answer plainly: ours as written, a bad escape is a 400, anything else a generic 502", () => {
  assert.deepEqual(toHttp(new HttpError(409, "closed")), { status: 409, message: "closed" });
  assert.equal(toHttp(new URIError("URI malformed")).status, 400);
  const e = toHttp(new TypeError("Cannot read properties of undefined (reading 'x')"));
  assert.equal(e.status, 502);
  assert.doesNotMatch(e.message, /Cannot read/);
});
