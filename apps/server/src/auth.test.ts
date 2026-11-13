import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { canonical, checkSigned, keyId, mustBeFrom, pairMessage } from "./auth.ts";

// a P-256 key like the Secure Enclave's, exported the way CryptoKit's x963Representation is
function device() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" }) as { x: string; y: string };
  const x963 = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")]).toString("base64url");
  return { key: x963, sign: (m: string) => sign("sha256", Buffer.from(m), { key: privateKey, dsaEncoding: "der" }).toString("base64url") };
}

const now = 1_800_000_000_000;
const body = JSON.stringify({ impressions: [{ petKey: "mochi", campaignId: "3", hook: 1 }] });

test("a fresh, correct device signature passes once", () => {
  const d = device(), seen = new Map<string, number>();
  const message = canonical("POST", "/impressions", String(now), body);
  const sig = d.sign(message);
  checkSigned({ key: d.key, time: String(now), sig, message, now: now + 500, seen });
  assert.throws(() => checkSigned({ key: d.key, time: String(now), sig, message, now: now + 900, seen }), (e: any) => e.status === 401 && /already used/.test(e.message));
});

test("tampered body, wrong key, old time and garbage are all 401/400", () => {
  const d = device(), other = device(), seen = new Map<string, number>();
  const message = canonical("POST", "/impressions", String(now), body);
  const sig = d.sign(message);
  const tampered = canonical("POST", "/impressions", String(now), body.replace('"hook":1', '"hook":2'));
  assert.throws(() => checkSigned({ key: d.key, time: String(now), sig, message: tampered, now, seen }), /bad device signature/);
  assert.throws(() => checkSigned({ key: other.key, time: String(now), sig, message, now, seen }), /bad device signature/);
  assert.throws(() => checkSigned({ key: d.key, time: String(now - 61_000), sig, message, now, seen }), /too far/);
  assert.throws(() => checkSigned({ key: "AAAA", time: String(now), sig, message, now, seen }), (e: any) => e.status === 400);
  assert.throws(() => checkSigned({ key: d.key, time: String(now), sig: "not-a-sig", message, now, seen }), /bad device signature/);
});

test("pairing message names the pet and a stable device id", () => {
  const d = device();
  assert.equal(keyId(d.key), keyId(d.key));
  assert.equal(keyId(d.key).length, 16);
  assert.match(pairMessage("mochi.gremlo.eth", keyId(d.key)), /Pet: mochi\.gremlo\.eth\nDevice: [0-9a-f]{16}$/);
});

test("a paired pet only accepts its own device; an unpaired pet still works unsigned", () => {
  const paired = { petKey: "0xA", devices: ["k1"] }, unpaired = { petKey: "0xB" };
  mustBeFrom(paired, { petKey: "0xA" });
  assert.throws(() => mustBeFrom(paired, null), (e: any) => e.status === 401 && /must be signed/.test(e.message));
  assert.throws(() => mustBeFrom(paired, { petKey: "0xB" }), /different pet/);
  mustBeFrom(unpaired, null);
  assert.throws(() => mustBeFrom(unpaired, { petKey: "0xA" }), /different pet/);
  // production: every request must be signed, paired or not
  assert.throws(() => mustBeFrom(unpaired, null, true), (e: any) => e.status === 401 && /pair this Mac/.test(e.message));
  mustBeFrom(paired, { petKey: "0xA" }, true);
});

test("NEP-413 owner signature: real ed25519, the exact message and recipient, full-access key, no nonce reuse", async () => {
  const { Account, KeyPair } = await import("near-api-js");
  const { signMessage } = await import("near-api-js/nep413");
  const { checkOwnerSignature } = await import("./auth.ts");
  const key = KeyPair.fromRandom("ed25519"), other = KeyPair.fromRandom("ed25519");
  const pk = key.getPublicKey().toString();
  // the chain's answer for this key: full access for the owner's key, function-call only for anything else
  const provider: any = { viewAccessKey: async ({ publicKey }: any) => ({ nonce: 0n, permission: String(publicKey) === pk ? "FullAccess" : { FunctionCall: { receiver_id: "x", method_names: [] } } }) };
  const sign = async (kp: typeof key, message: string, recipient = "vault.gremlo.testnet") => {
    const nonce = crypto.getRandomValues(new Uint8Array(32));
    const s = await signMessage({ signerAccount: new Account("owner.testnet", provider, kp.toString() as any), payload: { message, recipient, nonce } });
    return { signature: Buffer.from(s.signature).toString("base64"), publicKey: s.publicKey.toString(), nonce: Buffer.from(nonce).toString("base64") };
  };
  const used = new Set<string>();
  const msg = pairMessage("mochi", "abc123");
  const good = await sign(key, msg);
  await checkOwnerSignature(good, "owner.testnet", msg, "vault.gremlo.testnet", provider, used);
  await assert.rejects(checkOwnerSignature(good, "owner.testnet", msg, "vault.gremlo.testnet", provider, used), (e: any) => e.status === 401); // replay
  const code = async (body: object, m = msg) => checkOwnerSignature(body, "owner.testnet", m, "vault.gremlo.testnet", provider, new Set()).then(() => 200, (e: any) => e.status);
  assert.equal(await code(await sign(key, msg), pairMessage("mochi", "other-device")), 403); // signed a different message
  assert.equal(await code(await sign(key, msg, "evil.testnet")), 403); // signed for another recipient
  assert.equal(await code(await sign(other, msg)), 403); // not a full-access key of the owner
  // the same signature as base58 (some wallets send it that way), with and without the ed25519: prefix
  const { baseEncode } = await import("near-api-js");
  const again = await sign(key, msg);
  const b58 = baseEncode(Buffer.from(again.signature, "base64"));
  assert.equal(await code({ ...again, signature: b58 }), 200);
  const again2 = await sign(key, msg);
  assert.equal(await code({ ...again2, signature: "ed25519:" + baseEncode(Buffer.from(again2.signature, "base64")) }), 200);
  assert.equal(await code({ ...good, nonce: "AAAA" }), 400);
  assert.equal(await code({}), 400);
});

test("decodeSignature: base64, base64url and base58 give the same 64 bytes; anything else is empty", async () => {
  const { baseEncode } = await import("near-api-js");
  const { decodeSignature } = await import("./auth.ts");
  const raw = Buffer.from(Array.from({ length: 64 }, (_, i) => (i * 37 + 11) % 256));
  for (const enc of [raw.toString("base64"), raw.toString("base64url"), baseEncode(raw), "ed25519:" + baseEncode(raw)]) {
    assert.deepEqual(decodeSignature(enc), raw, enc);
  }
  for (const bad of ["", "abc", raw.subarray(0, 32).toString("base64"), "0OIl" + "1".repeat(80)]) assert.equal(decodeSignature(bad).length, 0, bad);
});
