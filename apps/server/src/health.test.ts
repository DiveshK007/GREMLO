import { test } from "node:test";
import assert from "node:assert/strict";
import { health, OPERATOR_LOW } from "./health.ts";

const base = { workerOn: true, everyMs: 600_000, startedAt: 0, lastOk: 1_000_000, lastError: null, operatorBalance: OPERATOR_LOW, expiredUnpaid: 0 };

test("health pages only for what needs a person", () => {
  assert.deepEqual(health(base, 1_000_000 + 60_000), { ok: true, reasons: [] });
  assert.match(health({ ...base, lastError: "RPC 429" }, 1_000_000 + 31 * 60_000).reasons[0], /no good pass in 31 min \(last error: RPC 429\)/);
  assert.ok(health({ ...base, workerOn: false }, 10 ** 12).ok, "a server with the worker off isn't stalled");
  assert.ok(!health({ ...base, operatorBalance: OPERATOR_LOW - 1n }, 1_000_000).ok);
  assert.ok(!health({ ...base, operatorBalance: null }, 1_000_000).ok, "unknown is not fine");
  assert.match(health({ ...base, expiredUnpaid: 2 }, 1_000_000).reasons[0], /2 views expired unpaid/);
  assert.ok(health({ ...base, lastOk: null, startedAt: 0 }, 60_000).ok, "a fresh start gets the same grace");
});
