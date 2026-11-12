import { test } from "node:test";
import assert from "node:assert/strict";
import { formatNear, formatWhen, parseNear } from "./config.ts";

test("NEAR amounts: exact 24-decimal parse and format, refusing anything else", () => {
  assert.equal(parseNear("0.001"), 1_000_000_000_000_000_000_000n);
  assert.equal(parseNear("1"), 10n ** 24n);
  assert.equal(parseNear("0.000000000000000000000001"), 1n);
  assert.equal(formatNear(500_000_000_000_000_000_000n), "0.0005");
  assert.equal(formatNear(10n ** 24n * 3n), "3");
  assert.equal(formatNear(1n), "0.000000000000000000000001");
  for (const s of ["0.1", "12.5", "0.000000000000000000000001", "100"]) assert.equal(formatNear(parseNear(s)), s);
  for (const bad of ["", "-1", "1e3", "0.0000000000000000000000001", "1,5", "abc", ".5"]) assert.throws(() => parseNear(bad));
});

test("formatWhen: one fixed 24-hour format, in the timezone given (the viewer's by default)", () => {
  const t = Date.UTC(2026, 10, 13, 16, 37, 18); // Fri 13 Nov 2026, 16:37:18 UTC
  assert.equal(formatWhen(t, "UTC"), "Fri 13 Nov, 16:37 UTC");
  assert.equal(formatWhen(t, "Asia/Kolkata"), "Fri 13 Nov, 22:07 GMT+5:30");
  assert.doesNotMatch(formatWhen(t, "America/New_York"), /am|pm/i);
});
