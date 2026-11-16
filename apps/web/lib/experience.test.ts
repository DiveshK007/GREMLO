import { test } from "node:test";
import assert from "node:assert/strict";
import { istWhen, modelName, near4, shortReq, split } from "./experience-format.ts";

test("near4: 4 decimals from yoctoNEAR, integer math, rounds half up", () => {
  assert.equal(near4("6000000000000000000000"), "0.0060");
  assert.equal(near4("4800000000000000000000"), "0.0048");
  assert.equal(near4("0"), "0.0000");
  assert.equal(near4(10n ** 24n * 12n + 5n * 10n ** 19n), "12.0001");
  assert.equal(near4("49999999999999999999"), "0.0000");
});

test("split: the compute share comes off the paid amount, nothing is lost", () => {
  const [devs, compute] = split(6_000_000_000_000_000_000_000n, 2000);
  assert.equal(near4(devs), "0.0048");
  assert.equal(near4(compute), "0.0012");
  const [d, c] = split(7n, 2000);
  assert.equal(d + c, 7n);
});

test("istWhen, shortReq, modelName", () => {
  assert.equal(istWhen(1794694845), "15 Nov, 03:50");
  assert.equal(shortReq("49b3f9cae70d48f8bca2aca2d7d97ae7"), "49b3f9ca…7ae7");
  assert.equal(shortReq("chatcmpl-5132d660-f00d-4cea-9ee6-832310f23900"), "chatcmpl-5132d660…");
  assert.equal(modelName("deepseek-ai/DeepSeek-V4.1-Flash-1017"), "DeepSeek-V4.1-Flash-1017");
});
