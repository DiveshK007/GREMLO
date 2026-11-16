import { SERVER_URL } from "./config";
import type { ActiveCampaign, PetPublic, PublicStats } from "./api";

// Server-side reads for /experience. The API's CORS allows only the production origin, so the browser never calls it
// here; the page is rendered on the server and revalidated.

export type Read<T> = { ok: true; data: T } | { ok: false };
export const REVALIDATE = 30;

async function read<T>(path: string): Promise<Read<T>> {
  try {
    const r = await fetch(`${SERVER_URL}${path}`, { next: { revalidate: REVALIDATE }, signal: AbortSignal.timeout(8000) });
    if (!r.ok) return { ok: false };
    return { ok: true, data: (await r.json()) as T };
  } catch {
    return { ok: false };
  }
}

export const DEMO_PET = process.env.NEXT_PUBLIC_DEMO_PET ?? "mochi";

export async function readLive() {
  const [stats, pet, campaign] = await Promise.all([
    read<PublicStats>("/stats"),
    read<PetPublic>(`/pets/${encodeURIComponent(DEMO_PET)}`),
    read<ActiveCampaign>("/campaigns/active"),
  ]);
  return { stats, pet, campaign, at: Date.now() };
}
