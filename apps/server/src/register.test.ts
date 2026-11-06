import { test } from "node:test";
import assert from "node:assert/strict";
import { HttpError, makeRegister, verifyWorldProof, type Verdict } from "./register.ts";

const proof = { protocol_version: "4.0", nonce: "0x1", action: "register-pet", responses: [{ nullifier: "42" }], environment: "production" };
const body = (pet: string) => ({
  petKey: pet,
  ownerAddress: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65",
  payoutAddress: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
  worldProof: proof,
});
const PET_A = "0x000000000000000000000000000000000000000a";
const PET_B = "0x000000000000000000000000000000000000000b";

function setup(verdict: Verdict, chain: () => Promise<string> = async () => "0xtx") {
  const store = { pets: {}, nullifiers: [] as string[] };
  const register = makeRegister({ verify: async () => verdict, registerOnChain: chain, store, save() {} });
  return { store, register };
}
const status = (p: Promise<unknown>, code: number) =>
  assert.rejects(p, (e) => e instanceof HttpError && e.status === code);

test("valid proof registers the pet and stores the nullifier", async () => {
  const { store, register } = setup({ ok: true, nullifier: "42" });
  const r = await register(body(PET_A));
  assert.deepEqual(r, { ok: true, txHash: "0xtx", name: PET_A.toLowerCase() });
  assert.deepEqual(store.nullifiers, ["42"]);
});

test("reused nullifier returns 409", async () => {
  const { register } = setup({ ok: true, nullifier: "42" });
  await register(body(PET_A));
  await assert.rejects(register(body(PET_B)), (e: any) => e.status === 409 && e.message === "already has a pet");
});

test("failed verify returns 403 and never touches the chain", async () => {
  let called = false;
  const { store, register } = setup({ ok: false, code: "all_verifications_failed" }, async () => { called = true; return "0x"; });
  await status(register(body(PET_A)), 403);
  assert.equal(called, false);
  assert.deepEqual(store.nullifiers, []);
});

test("a failed registerPet tx frees the nullifier for a retry", async () => {
  let fail = true;
  const { store, register } = setup({ ok: true, nullifier: "42" }, async () => {
    if (fail) throw new Error("reverted");
    return "0xtx";
  });
  await assert.rejects(register(body(PET_A)), /reverted/);
  assert.deepEqual(store.nullifiers, []);
  fail = false;
  await register(body(PET_A));
  assert.deepEqual(store.nullifiers, ["42"]);
});

test("two concurrent requests with one nullifier: one wins, one gets 409", async () => {
  const { register } = setup({ ok: true, nullifier: "42" }, () => new Promise((r) => setTimeout(() => r("0xtx"), 20)));
  const results = await Promise.allSettled([register(body(PET_A)), register(body(PET_B))]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal((results.find((r) => r.status === "rejected") as any).reason.status, 409);
});

const legacy = { proof: "0xabc", merkle_root: "0xdef", nullifier_hash: "0x2a", verification_level: "orb" };

test("registration does not check the proof shape: v4 and legacy both go to verify", async () => {
  for (const [i, p] of [proof, legacy].entries()) {
    const seen: unknown[] = [];
    const store = { pets: {}, nullifiers: [] as string[] };
    const register = makeRegister({ verify: async (r) => (seen.push(r), { ok: true, nullifier: "42" }), registerOnChain: async () => "0xtx", store, save() {} });
    assert.equal((await register({ ...body(PET_A), worldProof: p })).ok, true, `shape ${i}`);
    assert.deepEqual(seen, [p]); // handed over unchanged
  }
});

test("a missing or non-object worldProof is a 400", async () => {
  const { register } = setup({ ok: true, nullifier: "42" });
  for (const worldProof of [undefined, null, "proof", [1]]) await status(register({ ...body(PET_A), worldProof }), 400);
});

test("a nullifier reused across proof shapes is still a 409", async () => {
  const { register } = setup({ ok: true, nullifier: "42" });
  await register({ ...body(PET_A), worldProof: legacy });
  await status(register({ ...body(PET_B), worldProof: proof }), 409);
});

test("verifyWorldProof forwards the proof unchanged and trusts the portal's success", async (t) => {
  let sent = "";
  const reply = (status: number, json: unknown) => t.mock.method(globalThis, "fetch", async (url: string, init: any) => {
    assert.equal(url, "https://developer.worldcoin.org/api/v4/verify/rp_test");
    sent = init.body;
    return new Response(JSON.stringify(json), { status });
  });
  reply(200, { success: true, action: "register-pet", nullifier: "0x2a" });
  assert.deepEqual(await verifyWorldProof(proof, "rp_test"), { ok: true, nullifier: "42" }); // hex and decimal agree
  assert.equal(sent, JSON.stringify(proof));
  t.mock.restoreAll();
  reply(200, { success: true, nullifier: "0x2a", environment: "staging" }); // staging (simulator) is not ours to refuse
  assert.deepEqual(await verifyWorldProof(legacy, "rp_test"), { ok: true, nullifier: "42" });
  assert.equal(sent, JSON.stringify(legacy));
  t.mock.restoreAll();
  reply(400, { success: false, code: "all_verifications_failed" });
  assert.deepEqual(await verifyWorldProof(proof, "rp_test"), { ok: false, code: "all_verifications_failed" });
  t.mock.restoreAll();
  reply(200, { success: true, action: "other", nullifier: "0x2a" });
  assert.deepEqual(await verifyWorldProof(proof, "rp_test"), { ok: false, code: "wrong_action" });
});

test("nullifier comes from the portal answer, else from the field the proof's version binds", async (t) => {
  const run = async (portal: object, p: object) => {
    t.mock.method(globalThis, "fetch", async () => new Response(JSON.stringify({ success: true, ...portal })));
    const v = await verifyWorldProof(p, "rp_test");
    t.mock.restoreAll();
    return v;
  };
  const n42 = { ok: true, nullifier: "42" };
  assert.deepEqual(await run({ nullifier: "0x2a" }, legacy), n42);
  assert.deepEqual(await run({ nullifier_hash: "0x2a" }, { proof: "x" }), n42);
  assert.deepEqual(await run({ results: [{ success: false, nullifier: "0x1" }, { success: true, nullifier: "0x2a" }] }, {}), n42);
  assert.deepEqual(await run({}, legacy), n42); // legacy nullifier_hash
  assert.deepEqual(await run({}, { protocol_version: "4.0", responses: [{ identifier: "orb" }, { nullifier: "0x2a" }] }), n42); // nested v4
  assert.deepEqual(await run({}, { nullifier: "0x2a" }), n42); // bare nullifier
  // an extra top-level field on a v4 proof must not pick the nullifier
  assert.deepEqual(await run({}, { protocol_version: "4.0", nullifier: "0x1", responses: [{ nullifier: "0x2a" }] }), n42);
  assert.deepEqual(await run({}, { proof: "x" }), { ok: false, code: "no_nullifier" });
});
