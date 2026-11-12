import { recoverMessageAddress } from "viem";

// Checks a NEAR AI response signature (GET /v1/signature/{id}) against NEAR's attestation report:
// the EIP-191 signer recovered from `text` + `signature` must be the stated signing_address, and that address must be
// the attested key of the TEE that served the model (provider_tee) or of the gateway (gateway).
// Not checked here: the TDX/GPU quotes themselves, and the request/response hashes in `text` (they need the raw bytes).

export type Signature = { text?: string; signature?: string; signing_address?: string; signing_algo?: string; signature_kind?: string; error_code?: string; message?: string };
type Attested = { model_name?: string; signing_address?: string; signing_algo?: string; request_nonce?: string };
export type Report = { gateway_attestation?: Attested; model_attestations?: Attested[] };

const same = (a?: string, b?: string) => !!a && !!b && a.toLowerCase() === b.toLowerCase();

/** The model a provider_tee signature names (first field of `text`), or null. */
export const signedModel = (sig: Signature) => (sig.signature_kind === "provider_tee" && sig.text?.includes(":") ? sig.text.split(":")[0] : null);

/** Pure check. `recovered` is the EIP-191 signer of sig.text. Returns ok plus one line per finding. */
export function checkSignature(sig: Signature, report: Report | null, recovered: string | null, nonce: string) {
  if (!sig.signature || !sig.text || !sig.signing_address) {
    return { ok: false, lines: [`not signed: ${sig.error_code ?? "no signature"}${sig.message ? ` (${sig.message})` : ""}`] };
  }
  if (sig.signing_algo !== "ecdsa") return { ok: false, lines: [`unsupported signing_algo: ${sig.signing_algo}`] };
  if (!same(recovered ?? undefined, sig.signing_address)) {
    return { ok: false, lines: [`signature does not match: recovered ${recovered}, stated ${sig.signing_address}`] };
  }
  const lines = [`signature recovers to ${sig.signing_address}`];
  let match: Attested[] = [];
  if (sig.signature_kind === "provider_tee") {
    const model = signedModel(sig);
    match = (report?.model_attestations ?? []).filter((a) => a.model_name === model && same(a.signing_address, sig.signing_address) && a.signing_algo === "ecdsa");
    if (match.length !== 1) return { ok: false, lines: [...lines, `signer is not the one attested key for ${model} (${match.length} matches)`] };
    lines.push(`signer is the attested key of the NEAR TEE serving ${model}`);
  } else if (sig.signature_kind === "gateway") {
    const g = report?.gateway_attestation;
    if (!same(g?.signing_address, sig.signing_address)) return { ok: false, lines: [...lines, "signer is not the attested gateway key"] };
    match = [g!];
    lines.push("signer is the attested NEAR AI gateway key (binds the response to the gateway, not to a model TEE)");
  } else {
    return { ok: false, lines: [...lines, `unknown signature_kind: ${sig.signature_kind ?? "none"}`] };
  }
  if (match[0].request_nonce !== nonce) return { ok: false, lines: [...lines, "attestation report did not echo our nonce"] };
  return { ok: true, lines };
}

/** Fetches the signature and a fresh attestation report, then checks them. */
export async function verifyCompletion(id: string, opts: { key: string; base?: string; fetch?: typeof fetch; nonce: string }) {
  const base = opts.base ?? "https://cloud-api.near.ai/v1";
  const get = async (url: string, auth: boolean) => {
    const res = await (opts.fetch ?? fetch)(url, { headers: { Accept: "application/json", ...(auth ? { Authorization: `Bearer ${opts.key}` } : {}) } });
    const body = await res.json().catch(() => ({}));
    if (!res.ok && !body?.error_code) throw new Error(`HTTP ${res.status} from ${url.split("?")[0]}: ${JSON.stringify(body).slice(0, 200)}`);
    return body;
  };
  const sig: Signature = await get(`${base}/signature/${encodeURIComponent(id)}?signing_algo=ecdsa`, true);
  if (!sig.signature || !sig.text) return { sig, ...checkSignature(sig, null, null, opts.nonce) };
  const model = signedModel(sig);
  const q = new URLSearchParams({ signing_algo: "ecdsa", nonce: opts.nonce, ...(model ? { model, provider: "near" } : {}) });
  const report: Report = await get(`${base}/attestation/report?${q}`, false);
  const recovered = await recoverMessageAddress({ message: sig.text, signature: sig.signature as `0x${string}` }).catch(() => null);
  return { sig, ...checkSignature(sig, report, recovered, opts.nonce) };
}
