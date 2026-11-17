// The hook text of a campaign that is paid but not yet saved on the server. Kept on this device so a failed save
// can be retried, even after a reload. One draft at a time; storage can be missing or full, so every call is guarded.

export type Draft = {
  campaignId: string;
  hooks: string[];
  moments: string[];
  lineHash: string;
  brand: string;
  txHash: string;
  url: string;
  brief: { product: string; audience: string; offer: string; proof: string; cta: string };
  email?: string;
};
type Store = Pick<Storage, "getItem" | "setItem" | "removeItem">;
const KEY = "gremlo.unsavedCampaign";
const local = (): Store | null => {
  try {
    return localStorage;
  } catch {
    return null;
  }
};

export function keepDraft(d: Draft, s: Store | null = local()) {
  try {
    s?.setItem(KEY, JSON.stringify(d));
  } catch {
    /* storage full or blocked: the Retry button still works until reload */
  }
}
export function loadDraft(s: Store | null = local()): Draft | null {
  try {
    const d = JSON.parse(s?.getItem(KEY) ?? "null");
    return d && typeof d.campaignId === "string" && Array.isArray(d.hooks) && typeof d.txHash === "string" ? (d as Draft) : null;
  } catch {
    return null;
  }
}
export function clearDraft(s: Store | null = local()) {
  try {
    s?.removeItem(KEY);
  } catch {
    /* nothing to clear */
  }
}
