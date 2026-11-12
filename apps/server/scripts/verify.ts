// npm run verify <completion_id>: is this NEAR AI completion signed by an attested NEAR key? Exit 0 yes, 1 no.
import { randomBytes } from "node:crypto";
import { verifyCompletion } from "../src/verify.ts";

const id = process.argv[2];
if (!id) {
  console.error("usage: npm run verify <completion_id>");
  process.exit(2);
}
const r = await verifyCompletion(id, { key: process.env.NEAR_AI_API_KEY ?? "", base: process.env.NEAR_AI_BASE_URL || undefined, nonce: randomBytes(32).toString("hex") });
console.log(`completion ${id}`);
if (r.sig.signature_kind) console.log(`kind ${r.sig.signature_kind}, signer ${r.sig.signing_address}`);
if (r.sig.text) console.log(`signed text ${r.sig.text}`);
for (const l of r.lines) console.log(`- ${l}`);
console.log(r.ok ? "SIGNED: verified against NEAR's attestation report" : "NOT VERIFIED");
console.log("Not checked here: the hardware quotes and the request/response hashes. Full check: https://cloud.near.ai/verify");
process.exit(r.ok ? 0 : 1);
