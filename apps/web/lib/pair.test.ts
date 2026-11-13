import { test } from "node:test";
import assert from "node:assert/strict";
import { pairMessage } from "./pair.ts";

test("the pairing message is byte-identical to what the server verifies", () => {
  assert.equal(pairMessage("mochi", "3fa9c2e1b0d4a7f6"), "Pair this device to my pet.\nPet: mochi\nDevice: 3fa9c2e1b0d4a7f6");
});
