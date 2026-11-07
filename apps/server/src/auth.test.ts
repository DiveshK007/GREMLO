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
  assert.match(pairMessage("mochi.notchi.eth", keyId(d.key)), /Pet: mochi\.notchi\.eth\nDevice: [0-9a-f]{16}$/);
});

test("a paired pet only accepts its own device; an unpaired pet still works unsigned", () => {
  const paired = { petKey: "0xA", devices: ["k1"] }, unpaired = { petKey: "0xB" };
  mustBeFrom(paired, { petKey: "0xA" });
  assert.throws(() => mustBeFrom(paired, null), (e: any) => e.status === 401 && /must be signed/.test(e.message));
  assert.throws(() => mustBeFrom(paired, { petKey: "0xB" }), /different pet/);
  mustBeFrom(unpaired, null);
  assert.throws(() => mustBeFrom(unpaired, { petKey: "0xA" }), /different pet/);
});
