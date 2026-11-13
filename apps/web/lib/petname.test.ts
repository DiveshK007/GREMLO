import { test } from "node:test";
import assert from "node:assert/strict";
import { cleanPetName, nameCandidates, validPetName } from "./petname.ts";

test("one pet-name rule, the field's cleaning, and the next free names", () => {
  assert.ok(validPetName("mochi-2") && !validPetName("m") && !validPetName("a".repeat(25)) && !validPetName("Mochi") && !validPetName("-mochi") && !validPetName("mochi-"));
  assert.equal(cleanPetName("Mochi Bean!"), "mochibean");
  assert.deepEqual(nameCandidates("mochi").slice(0, 2), ["mochi-2", "mochi-3"]);
  for (const c of nameCandidates("a".repeat(24))) assert.ok(validPetName(c), c);
});
