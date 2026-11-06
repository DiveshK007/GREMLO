import { test } from "node:test";
import assert from "node:assert/strict";
import { addThought } from "./thoughts.ts";

test("records thoughts with a request id, newest first, capped at 10", () => {
  let list = addThought([], { action: "work", requestId: "r1" }, 1_000_000);
  assert.deepEqual(list, [{ action: "work", requestId: "r1", at: 1000 }]);
  for (let i = 2; i <= 12; i++) list = addThought(list, { action: "wave", requestId: `r${i}` });
  assert.equal(list.length, 10);
  assert.equal(list[0].requestId, "r12");
});

test("a sleep without a request id adds nothing", () => {
  const list = [{ action: "work", requestId: "r1", at: 1 }];
  assert.equal(addThought(list, { action: "sleep", requestId: null }), list);
});
