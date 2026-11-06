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
 * Forwards the IDKit result unchanged to the Developer Portal v4 verify endpoint
 * (POST https://developer.world.org/api/v4/verify/{rp_id}, per docs.world.org/api-reference/developer-portal/verify).
 * Network or portal outages throw, so they surface as 502 rather than a false "denied".
 */
export async function verifyWorldProof(result: unknown, rpId: string, environment = "production"): Promise<Verdict> {
  const res = await fetch(`https://developer.world.org/api/v4/verify/${encodeURIComponent(rpId)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(result),
    signal: AbortSignal.timeout(10_000),
  });
  if (res.status >= 500) throw new Error(`World verify unavailable (${res.status})`);
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok || json.success !== true) return { ok: false, code: json.code ?? `http_${res.status}` };
  if (json.environment && json.environment !== environment) return { ok: false, code: "wrong_environment" };
  if (json.action && json.action !== REGISTER_ACTION) return { ok: false, code: "wrong_action" };
  const nullifier = canonical(json.nullifier ?? json.results?.find((r: any) => r?.success)?.nullifier);
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
    // v4 uniqueness proofs only, so there is one nullifier space to track
    if (proof?.protocol_version !== "4.0" || proof.action !== REGISTER_ACTION || !Array.isArray(proof.responses)) {
      throw bad("worldProof must be an IDKit v4 result for action register-pet");
    }
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
