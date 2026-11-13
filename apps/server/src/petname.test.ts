import { test } from "node:test";
import assert from "node:assert/strict";
import { validPetName } from "./register.ts";

test("one pet-name rule: 2-24 of a-z, 0-9 and dashes, no dash at either end", () => {
  for (const ok of ["mo", "mochi", "mochi-2", "a".repeat(24)]) assert.ok(validPetName(ok), ok);
  for (const no of ["m", "a".repeat(25), "Mochi", "mochi.gremlo", "mo chi", "-mochi", "mochi-", "", 5, null]) assert.ok(!validPetName(no), String(no));
});
