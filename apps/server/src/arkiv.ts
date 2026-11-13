import { createPublicClient, createWalletClient, ExpirationTime } from "@arkiv-network/sdk";
import { rabdi } from "@arkiv-network/sdk/chains";
import { eq } from "@arkiv-network/sdk/query";
import { addr, defineSchema, str, u256, u64 } from "@arkiv-network/sdk/schema";
import { http, isHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// Public, self-expiring mirror of campaign data on Arkiv. The server's own store stays the source of truth;
// briefs, proof points and anything about a person never go here. Off unless ARKIV_ACCESS_KEY and ARKIV_KEY are set.

export const CampaignCard = defineSchema("gremlo.campaign", {
  campaignId: u64().indexed(),
  brand: addr().indexed(),
  hooks: str(), // the picked hooks, one per line
  url: str(),
  rateWei: u256(),
  endTime: u64(),
  sourceChainId: u64(),
  fundingTx: str(),
});

export const Receipt = defineSchema("gremlo.receipt", {
  campaignId: u64().indexed(),
  pet: addr().indexed(),
  views: u64(),
  amountWei: u256(),
  settleTx: str().indexed(),
  sourceChainId: u64(),
});

const GRACE_S = 3600; // CampaignVault.SETTLE_GRACE
/** Cards live until a week after the settlement window; receipts a month after the campaign ends. */
export const cardExpiry = (endTime: bigint) => new Date((Number(endTime) + GRACE_S + 7 * 86400) * 1000);
export const receiptExpiry = (endTime: bigint) => new Date((Number(endTime) + 30 * 86400) * 1000);
export const EXPLORER = "https://rabdi.explorer.arkiv.network";

const accessKey = process.env.ARKIV_ACCESS_KEY, key = process.env.ARKIV_KEY;
// Off unless ARKIV=on as well: the NEAR build never talks to Arkiv by accident (its schema is EVM-only).
export const arkivOn = process.env.ARKIV === "on" && !!(accessKey && key && isHex(key));
const chain = rabdi({ accessKey: accessKey ?? "" });
const read = createPublicClient({ chain, transport: http() });
const write = arkivOn ? createWalletClient({ chain, transport: http(), account: privateKeyToAccount(key as `0x${string}`) }) : null;

/** Fire-and-forget publish: returns the entity key, or null when Arkiv is off or the write failed (logged). */
async function publish(label: string, run: () => Promise<{ entityKey: string; txHash: string }>) {
  if (!write) return null;
  try {
    const r = await run();
    console.log(`arkiv: ${label} ${r.entityKey} tx ${r.txHash}`);
    return r.entityKey;
  } catch (e) {
    console.error(`arkiv: ${label} not published: ${(e as Error).message.split("\n")[0]}`);
    return null;
  }
}

export const publishCampaign = (c: { id: string; brand: `0x${string}`; hooks: string[]; url: string; rateWei: bigint; endTime: bigint; chainId: number; fundingTx: string }) =>
  publish(`campaign ${c.id}`, () => write!.createEntity(CampaignCard, {
    campaignId: u64(BigInt(c.id)), brand: addr(c.brand), hooks: c.hooks.join("\n"), url: c.url,
    rateWei: c.rateWei, endTime: u64(c.endTime), sourceChainId: u64(BigInt(c.chainId)), fundingTx: c.fundingTx,
  }, { expiration: ExpirationTime.atDate(cardExpiry(c.endTime), { atLeast: ExpirationTime.fromDays(1) }) }));

export const publishReceipt = (r: { campaignId: string; pet: `0x${string}`; views: number; amountWei: bigint; settleTx: string; chainId: number; endTime: bigint }) =>
  publish(`receipt ${r.settleTx}`, () => write!.createEntity(Receipt, {
    campaignId: u64(BigInt(r.campaignId)), pet: addr(r.pet), views: u64(BigInt(r.views)), amountWei: r.amountWei,
    settleTx: r.settleTx, sourceChainId: u64(BigInt(r.chainId)),
  }, { expiration: ExpirationTime.atDate(receiptExpiry(r.endTime), { atLeast: ExpirationTime.fromDays(1) }) }));

/** What Arkiv holds for a campaign, read back from Arkiv itself (not from our store). */
export async function arkivCampaign(id: string) {
  if (!arkivOn) return { on: false as const };
  const [cards, receipts] = await Promise.all([
    read.select({ $key: true, $expiresAt: true, hooks: true, url: true, rateWei: true, endTime: true, fundingTx: true }).from(CampaignCard).where(eq("campaignId", u64(BigInt(id)))).limit(1).fetch(),
    read.select({ $key: true, pet: true, views: true, amountWei: true, settleTx: true }).from(Receipt).where(eq("campaignId", u64(BigInt(id)))).limit(100).fetch(),
  ]);
  const card = cards.entities[0];
  return {
    on: true as const,
    explorer: EXPLORER,
    card: card ? { key: card.$key, expiresAt: String(card.$expiresAt), hooks: card.hooks.value.split("\n"), url: card.url.value, rateWei: String(card.rateWei.value), fundingTx: card.fundingTx.value } : null,
    receipts: receipts.entities.map((r) => ({ key: r.$key, pet: r.pet.value, views: Number(r.views.value), amountWei: String(r.amountWei.value), settleTx: r.settleTx.value })),
  };
}
