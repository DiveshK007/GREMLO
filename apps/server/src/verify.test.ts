import { test } from "node:test";
import assert from "node:assert/strict";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { checkSignature, verifyCompletion, type Report } from "./verify.ts";

const MODEL = "Qwen/Qwen3.8-27B", NONCE = "ab".repeat(32);
const tee = privateKeyToAccount(generatePrivateKey()), gw = privateKeyToAccount(generatePrivateKey());
const report = (addr = tee.address, nonce = NONCE): Report => ({
  gateway_attestation: { signing_address: gw.address, signing_algo: "ecdsa", request_nonce: nonce },
  model_attestations: [{ model_name: MODEL, signing_address: addr, signing_algo: "ecdsa", request_nonce: nonce }],
});
// a fake NEAR AI: signature endpoint needs the key, the report is public
const api = (sig: object, rep: Report) => async (url: string | URL | Request, init?: RequestInit) => {
  const u = String(url);
  if (u.includes("/signature/")) {
    assert.equal((init?.headers as Record<string, string>).Authorization, "Bearer k");
    return Response.json(sig);
  }
  assert.ok(u.includes(`model=${encodeURIComponent(MODEL)}`) && u.includes("provider=near") && u.includes(`nonce=${NONCE}`), u);
  return Response.json(rep);
};

test("a provider_tee signature from the attested model key verifies, with real secp256k1 recovery", async () => {
  const text = `${MODEL}:${"1".repeat(64)}:${"2".repeat(64)}`;
  const sig = { text, signature: await tee.signMessage({ message: text }), signing_address: tee.address, signing_algo: "ecdsa", signature_kind: "provider_tee" };
  const r = await verifyCompletion("c1", { key: "k", nonce: NONCE, fetch: api(sig, report()) as typeof fetch });
  assert.equal(r.ok, true, r.lines.join("; "));
  assert.match(r.lines.at(-1)!, /attested key of the NEAR TEE serving Qwen/);
});

test("refuses: forged signer, key not in the report, stale nonce, unknown kind, no signature", async () => {
  const text = `${MODEL}:a:b`, signature = await tee.signMessage({ message: text });
  const base = { text, signature, signing_address: tee.address, signing_algo: "ecdsa", signature_kind: "provider_tee" };
  assert.match(checkSignature({ ...base, signing_address: gw.address }, report(), tee.address, NONCE).lines[0], /does not match/);
  assert.match(checkSignature(base, report(gw.address), tee.address, NONCE).lines.at(-1)!, /not the one attested key/);
  assert.match(checkSignature(base, report(tee.address, "00"), tee.address, NONCE).lines.at(-1)!, /nonce/);
  assert.match(checkSignature({ ...base, signature_kind: "other" }, report(), tee.address, NONCE).lines.at(-1)!, /unknown signature_kind/);
  const none = checkSignature({ error_code: "signature_unavailable", message: "expired" }, null, null, NONCE);
  assert.deepEqual(none, { ok: false, lines: ["not signed: signature_unavailable (expired)"] });
});

test("a gateway signature verifies against the gateway key and says what it binds", () => {
  const r = checkSignature({ text: "a:b", signature: "0x1", signing_address: gw.address, signing_algo: "ecdsa", signature_kind: "gateway" }, report(), gw.address, NONCE);
  assert.equal(r.ok, true);
  assert.match(r.lines.at(-1)!, /gateway, not to a model TEE/);
});
