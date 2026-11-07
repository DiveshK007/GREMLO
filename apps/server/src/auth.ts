import { createHash, createPublicKey, verify } from "node:crypto";
import { HttpError } from "./register.ts";

// Device signatures: each Mac install holds a P-256 key in the Secure Enclave. Requests that cost or earn money
// carry a DER ECDSA signature over a canonical string, so a view, think or click can't be forged by a script.

export const MAX_SKEW_MS = 60_000;
const b64u = (b: Buffer) => b.toString("base64url");

/** What the device signs: method, path, unix ms, and the SHA-256 of the body ("" for none). */
export function canonical(method: string, path: string, time: string, body: string) {
  return `${method.toUpperCase()}\n${path}\n${time}\n${createHash("sha256").update(body).digest("hex")}`;
}

/** X9.63 uncompressed P-256 public key (65 bytes, base64url) to a Node KeyObject; throws 400 if malformed. */
export function deviceKey(x963b64u: string) {
  const raw = Buffer.from(x963b64u, "base64url");
  if (raw.length !== 65 || raw[0] !== 4) throw new HttpError(400, "device key must be a 65-byte P-256 public key");
  return createPublicKey({ key: { kty: "EC", crv: "P-256", x: b64u(raw.subarray(1, 33)), y: b64u(raw.subarray(33)) }, format: "jwk" });
}

/** Short stable id for a device key, for storage and logs. */
export const keyId = (x963b64u: string) => createHash("sha256").update(Buffer.from(x963b64u, "base64url")).digest("hex").slice(0, 16);

/**
 * Checks a device signature: the key, a fresh timestamp, an unused signature. `seen` remembers signatures for
 * twice the skew window so a captured request can't be replayed. Throws 401 with the reason.
 */
export function checkSigned(opts: { key: string; time: string; sig: string; message: string; now: number; seen: Map<string, number> }) {
  const t = Number(opts.time);
  if (!Number.isFinite(t) || Math.abs(opts.now - t) > MAX_SKEW_MS) throw new HttpError(401, "signature time is too far from now");
  for (const [s, at] of opts.seen) if (opts.now - at > 2 * MAX_SKEW_MS) opts.seen.delete(s);
  if (opts.seen.has(opts.sig)) throw new HttpError(401, "signature already used");
  let ok = false;
  try {
    ok = verify("sha256", Buffer.from(opts.message), { key: deviceKey(opts.key), dsaEncoding: "der" }, Buffer.from(opts.sig, "base64url"));
  } catch (e) {
    if (e instanceof HttpError) throw e;
  }
  if (!ok) throw new HttpError(401, "bad device signature");
  opts.seen.set(opts.sig, opts.now);
}

/** The message a pet owner signs with their wallet to pair a device to their pet. */
export const pairMessage = (petName: string, deviceKeyId: string) =>
  `Pair this device to my Notchi pet.\nPet: ${petName}\nDevice: ${deviceKeyId}`;
