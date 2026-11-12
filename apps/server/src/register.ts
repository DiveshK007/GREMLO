import { keccak256, stringToBytes } from "viem";

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export const bad = (msg: string) => new HttpError(400, msg);
/** NEAR account id rules (nomicon): 2-64 chars, lowercase parts joined by "." with "-" or "_" inside a part. */
export const isAccountId = (v: unknown): v is string =>
  typeof v === "string" && v.length >= 2 && v.length <= 64 && /^(([a-z\d]+[-_])*[a-z\d]+\.)*([a-z\d]+[-_])*[a-z\d]+$/.test(v);
export const accountId = (v: unknown, field: string) => {
  if (!isAccountId(v)) throw bad(`${field} must be a NEAR account id, like mochi.testnet`);
  return v;
};

/** World ID actions this server signs for. Anything else gets a 400. */
export const WORLD_ACTIONS = new Set(["register-pet", "approve-spend"]);
const REGISTER_ACTION = "register-pet";

export type Verdict = { ok: true; nullifier: string } | { ok: false; code: string };
export type PetRecord = { name: string; petKey: string; owner: string; payout: string; registerTx: string; verifyTx?: string; devices?: string[] }; // petKey = name = the vault pet_id; owner/payout are NEAR accounts; devices: paired Secure Enclave keys (X9.63, base64url)

/** Same number whether it arrives as decimal (IDKit) or 0x hex (Developer Portal). */
const canonical = (n: unknown) => {
  try { return typeof n === "string" && n ? BigInt(n).toString() : null; } catch { return null; }
};

/**
 * The nullifier of a verified proof. The portal's own answer comes first. Only if it does not echo one
 * do we read it from the proof, and then from the field the proof's own version binds (v4 responses[],
 * legacy nullifier_hash), so a stray extra field cannot pick the nullifier.
 */
function findNullifier(json: any, proof: any) {
  const fromPortal = json.nullifier ?? json.nullifier_hash ?? json.results?.find((r: any) => r?.success)?.nullifier;
  const v4 = String(proof?.protocol_version ?? "").startsWith("4") || Array.isArray(proof?.responses);
  const fromProof = v4
    ? proof?.responses?.find((r: any) => r?.nullifier)?.nullifier
    : proof?.nullifier_hash ?? proof?.nullifier;
  return canonical(fromPortal ?? fromProof);
}

let loggedShape = false;
const WORLD_API = process.env.WORLD_API_BASE ?? "https://developer.worldcoin.org"; // overridden only by the e2e test (Anvil only, see index.ts)

/**
 * Forwards the IDKit result unchanged to the Developer Portal v4 verify endpoint
 * (POST https://developer.worldcoin.org/api/v4/verify/{rp_id}) and trusts its `success`.
 * Network or portal outages throw, so they surface as 502 rather than a false "denied".
 */
export async function verifyWorldProof(result: unknown, rpId: string, action = REGISTER_ACTION): Promise<Verdict> {
  if (!loggedShape) {
    loggedShape = true;
    console.log(`worldProof top-level keys: ${Object.keys(result as object).join(", ")}`); // keys only, never values
  }
  const res = await fetch(`${WORLD_API}/api/v4/verify/${encodeURIComponent(rpId)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(result),
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status >= 500) throw new Error(`World verify unavailable (${res.status})`);
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok || json.success !== true) return { ok: false, code: json.code ?? `http_${res.status}` };
  if (json.action && json.action !== action) return { ok: false, code: "wrong_action" };
  const nullifier = findNullifier(json, result);
  return nullifier ? { ok: true, nullifier } : { ok: false, code: "no_nullifier" };
}

/** IDKit's hashSignal for a string signal: keccak of the UTF-8 bytes, shifted into the field, 32-byte hex. */
export const signalHash = (signal: string) => `0x${(BigInt(keccak256(stringToBytes(signal))) >> 8n).toString(16).padStart(64, "0")}`;

/**
 * The proof must be made for this owner (the web passes signal = the owner's NEAR account id), so a proof seen once
 * can't register a pet for someone else's account. Every signal_hash in the result must match, and there must be one.
 */
export function signalMatches(proof: any, owner: string) {
  const hashes = [proof?.signal_hash, ...(Array.isArray(proof?.responses) ? proof.responses.map((r: any) => r?.signal_hash) : [])]
    .filter((h) => h !== undefined && h !== null);
  const want = signalHash(owner);
  return hashes.length > 0 && hashes.every((h) => typeof h === "string" && h.toLowerCase() === want);
}

export function makeRegister(deps: {
  verify: (result: unknown) => Promise<Verdict>;
  registerOnChain: (pet: string, owner: string, payout: string) => Promise<{ registerTx: string; verifyTx: string }>;
  accountExists: (id: string) => Promise<boolean>;
  store: { pets: Record<string, PetRecord>; nullifiers: string[] };
  save: () => void;
}) {
  const claiming = new Set<string>(); // nullifiers with a registration in flight

  return async function registerPet(body: any) {
    const owner = accountId(body.owner, "owner");
    const payout = accountId(body.payout ?? owner, "payout");
    const name = body.name;
    if (typeof name !== "string" || !/^[a-z0-9.-]{2,64}$/.test(name)) throw bad("name must be 2-64 characters of a-z, 0-9, . or -");
    const petKey = name; // the vault's pet_id
    const proof = body.worldProof;
    // shape is the portal's call, not ours; we only need something to forward
    if (!proof || typeof proof !== "object" || Array.isArray(proof)) throw bad("worldProof is required");
    const { pets, nullifiers } = deps.store;
    if (!signalMatches(proof, owner)) throw new HttpError(403, "World proof rejected: it was made for a different NEAR account");

    // a transfer to a missing account fails and leaves the NEAR stuck in the vault, so refuse it up front
    for (const [field, id] of [["owner", owner], ["payout", payout]] as const) {
      if (!(await deps.accountExists(id))) throw bad(`${field} account ${id} does not exist on NEAR yet; create it first`);
    }
    // World first: a returning human must hear "already has a pet", not a name clash with their own pet
    const verdict = await deps.verify(proof);
    if (!verdict.ok) throw new HttpError(403, `World proof rejected: ${verdict.code}`);
    const n = verdict.nullifier;
    if (nullifiers.includes(n) || claiming.has(n)) throw new HttpError(409, "already has a pet");
    if (pets[name] || Object.values(pets).some((p) => p.petKey === petKey)) throw new HttpError(409, "pet already registered");

    claiming.add(n);
    try {
      // the nullifier is kept only once the pet exists onchain, so a failed tx can be retried
      const { registerTx, verifyTx } = await deps.registerOnChain(petKey, owner, payout);
      pets[name] = { name, petKey, owner, payout, registerTx, verifyTx };
      nullifiers.push(n);
      deps.save();
      return { ok: true, txHash: registerTx, verifyTx, name }; // shape apps/web expects
    } finally {
      claiming.delete(n);
    }
  };
}
