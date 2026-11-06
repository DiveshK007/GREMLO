import { SERVER_URL } from "./config";

/**
 * All calls to apps/server live here. If a route or body shape on the server differs,
 * change it in this one file.
 */

export class ApiError extends Error {
  constructor(public status: number, message: string, public body?: unknown) {
    super(message);
  }
}

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${SERVER_URL}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
    });
  } catch {
    throw new ApiError(0, `Can't reach the Notchi server at ${SERVER_URL}. Is it running?`);
  }
  const text = await res.text();
  let body: unknown = undefined;
  try {
    body = text ? JSON.parse(text) : undefined;
  } catch {
    body = text;
  }
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    if (typeof body === "string" && body) msg = body;
    else if (body && typeof body === "object") {
      const err = (body as Record<string, unknown>).error;
      if (typeof err === "string") msg = err;
      else if (err && typeof err === "object" && typeof (err as Record<string, unknown>).message === "string")
        msg = (err as Record<string, string>).message;
    }
    throw new ApiError(res.status, msg, body);
  }
  return body as T;
}

/** GET /world/sign?action=... -> RP signature for IDKit (the signing key never leaves the server). */
export type WorldSig = { sig: string; nonce: string; created_at: number | string; expires_at: number | string };
export const worldSign = (action: string) => call<WorldSig>(`/world/sign?action=${encodeURIComponent(action)}`);

/** POST /pets/register -> server verifies the World proof, stores the nullifier, calls registerPet. 409 = already has a pet. */
export type RegisterBody = {
  name: string;
  petKey: string;
  ownerAddress: string;
  payoutAddress: string;
  worldProof: unknown;
};
export const registerPet = (body: RegisterBody) =>
  call<{ ok?: boolean; txHash?: string; name?: string }>(`/pets/register`, { method: "POST", body: JSON.stringify(body) });

/** POST /campaigns/lines -> the pet writes 3 ad lines through 0G. */
export type SuggestedLine = { text: string; requestId?: string | null };
export const suggestLines = (brief: string) =>
  call<{ lines: SuggestedLine[] }>(`/campaigns/lines`, { method: "POST", body: JSON.stringify({ brief }) });

/** POST /campaigns -> tell the server the line text for an onchain campaign (the chain stores only its hash). */
export const recordCampaign = (body: { campaignId: string; line: string; lineHash: string; brand: string; txHash: string }) =>
  call<unknown>(`/campaigns`, { method: "POST", body: JSON.stringify(body) });
