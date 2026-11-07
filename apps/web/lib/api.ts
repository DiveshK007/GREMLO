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

/** A brand's brief. Proof points are the only claims hooks may use (one per line). */
export type Brief = { product: string; audience: string; offer: string; proof: string; cta: string };
export const FORMATS = ["humour", "sarcasm", "offer", "question", "bold-claim", "urgency", "story", "dev-meme"] as const;
export type Hook = { format: (typeof FORMATS)[number] | "own"; text: string; requestId?: string | null };
export type Dropped = { format: string; text: string; reason: string };

/** POST /campaigns/hooks -> 2 hooks per format from 0G, each through the claim checks. */
export const suggestHooks = (brief: Brief, url: string) =>
  call<{ hooks: Hook[]; dropped: Dropped[]; requestId: string }>(`/campaigns/hooks`, {
    method: "POST",
    body: JSON.stringify({ brief, url, attest: true }),
  });

/** POST /campaigns/check -> the same checks the server runs after payment, run before it. */
export const checkCampaign = (brief: Brief, hooks: string[], url: string) =>
  call<{ ok: true; url: string }>(`/campaigns/check`, { method: "POST", body: JSON.stringify({ brief, hooks, url }) });

/** GET /campaigns/:id/stats -> per-hook views and clicks, queued views. */
export type Stats = { campaignId: string; url: string | null; views: number[]; clicks: number[]; pendingViews: number };
export const campaignStats = (id: string) => call<Stats>(`/campaigns/${encodeURIComponent(id)}/stats`);

/** POST /campaigns -> tell the server the line text for an onchain campaign (the chain stores only its hash). */
export const recordCampaign = (body: { campaignId: string; hooks: string[]; lineHash: string; brand: string; txHash: string; url: string; brief: Brief }) =>
  call<unknown>(`/campaigns`, { method: "POST", body: JSON.stringify(body) });

/** POST /settle/:id -> the server pays queued impressions onchain, one tx per pet. amount is wei as a string. */
export type Settlement = {
  txHash: string | null;
  count: number;
  amount: string;
  settled: { petKey: string; count: number; amount: string; txHash: string }[];
  error?: string;
  seeded?: boolean;
};
export const settleImpressions = (campaignId: string) =>
  call<Settlement>(`/settle/${encodeURIComponent(campaignId)}`, { method: "POST" });

/** GET /campaigns/active -> what the pet is showing now, or null when nothing is live. */
export type ActiveCampaign = { campaignId: string; line: string | null; hooks: string[]; url: string | null; order?: number[]; brand: string; ratePerImpression: string } | null;
export const activeCampaign = () => call<ActiveCampaign>(`/campaigns/active`);

/** GET /stats -> homepage numbers from the chain's own events. */
export type PublicStats = { campaigns: number; settledViews: string; paidWei: string; pets: number; chainId: number; seeded: boolean };
export const publicStats = () => call<PublicStats>(`/stats`);

/** POST /try -> 3 example hooks for the homepage; rate-limited, labelled as examples. */
export const tryHook = (product: string, audience: string) =>
  call<{ hooks: Hook[]; requestId: string; example: true }>(`/try`, { method: "POST", body: JSON.stringify({ product, audience }) });
