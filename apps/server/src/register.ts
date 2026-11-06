import { getAddress, isAddress } from "viem";

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export const bad = (msg: string) => new HttpError(400, msg);
export const addr = (v: unknown, field: string) => {
  if (typeof v !== "string" || !isAddress(v)) throw bad(`${field} must be an address`);
  return getAddress(v);
};

/** World ID actions this server signs for. Anything else gets a 400. */
export const WORLD_ACTIONS = new Set(["register-pet"]);
const REGISTER_ACTION = "register-pet";

export type Verdict = { ok: true; nullifier: string } | { ok: false; code: string };
export type PetRecord = { name: string; petKey: string; owner: string; payout: string; registerTx: string };

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

/**
 * Forwards the IDKit result unchanged to the Developer Portal v4 verify endpoint
 * (POST https://developer.worldcoin.org/api/v4/verify/{rp_id}) and trusts its `success`.
 * Network or portal outages throw, so they surface as 502 rather than a false "denied".
 */
export async function verifyWorldProof(result: unknown, rpId: string): Promise<Verdict> {
  if (!loggedShape) {
    loggedShape = true;
    console.log(`worldProof top-level keys: ${Object.keys(result as object).join(", ")}`); // keys only, never values
  }
  const res = await fetch(`https://developer.worldcoin.org/api/v4/verify/${encodeURIComponent(rpId)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(result),
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status >= 500) throw new Error(`World verify unavailable (${res.status})`);
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok || json.success !== true) return { ok: false, code: json.code ?? `http_${res.status}` };
  if (json.action && json.action !== REGISTER_ACTION) return { ok: false, code: "wrong_action" };
  const nullifier = findNullifier(json, result);
  return nullifier ? { ok: true, nullifier } : { ok: false, code: "no_nullifier" };
}

export function makeRegister(deps: {
  verify: (result: unknown) => Promise<Verdict>;
  registerOnChain: (pet: string, owner: string, payout: string) => Promise<string>;
  store: { pets: Record<string, PetRecord>; nullifiers: string[] };
  save: () => void;
}) {
  const claiming = new Set<string>(); // nullifiers with a registration in flight

  return async function registerPet(body: any) {
    const petKey = addr(body.petKey, "petKey");
    const owner = addr(body.ownerAddress, "ownerAddress");
    const payout = addr(body.payoutAddress, "payoutAddress");
    const name = body.name ?? petKey.toLowerCase();
    if (typeof name !== "string" || !/^[a-z0-9.-]{1,64}$/.test(name)) throw bad("name must be a-z, 0-9, . or -");
    const proof = body.worldProof;
    // shape is the portal's call, not ours; we only need something to forward
    if (!proof || typeof proof !== "object" || Array.isArray(proof)) throw bad("worldProof is required");
    const { pets, nullifiers } = deps.store;
    if (pets[name] || Object.values(pets).some((p) => p.petKey === petKey)) throw new HttpError(409, "pet already registered");

    const verdict = await deps.verify(proof);
    if (!verdict.ok) throw new HttpError(403, `World proof rejected: ${verdict.code}`);
    const n = verdict.nullifier;
    if (nullifiers.includes(n) || claiming.has(n)) throw new HttpError(409, "already has a pet");

    claiming.add(n);
    try {
      // the nullifier is kept only once the pet exists onchain, so a failed tx can be retried
      const registerTx = await deps.registerOnChain(petKey, owner, payout);
      pets[name] = { name, petKey, owner, payout, registerTx };
      nullifiers.push(n);
      deps.save();
      return { ok: true, txHash: registerTx, name }; // shape apps/web expects
    } finally {
      claiming.delete(n);
    }
  };
}
