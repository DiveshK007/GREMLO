import { test } from "node:test";
import assert from "node:assert/strict";
import { checkViewable } from "./viewable.ts";

test("viewability: 5 s on screen, unlocked, visible, someone at the Mac", () => {
  const ok = { shownMs: 5000, unlocked: true, visible: true, idleS: 12 };
  assert.doesNotThrow(() => checkViewable(ok));
  assert.throws(() => checkViewable({ ...ok, shownMs: 4999 }), /under 5 seconds/);
  assert.throws(() => checkViewable({ ...ok, unlocked: false }), /locked/);
  assert.throws(() => checkViewable({ ...ok, visible: "yes" }), /covered/);
  assert.throws(() => checkViewable({ ...ok, idleS: 301 }), /nobody/);
  assert.throws(() => checkViewable({ petKey: "x" }), /under 5 seconds/); // old clients without fields don't count
});
