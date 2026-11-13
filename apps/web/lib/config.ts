// The product name, in one place, for every user-facing string in the web app.
export const PRODUCT = "Gremlo";

export const SERVER_URL = process.env.NEXT_PUBLIC_SERVER_URL ?? "http://localhost:8787";
export const WORLD_APP_ID = process.env.NEXT_PUBLIC_WORLD_APP_ID ?? "";
export const WORLD_RP_ID = process.env.NEXT_PUBLIC_WORLD_RP_ID ?? "";
export const WORLD_PRESET = process.env.NEXT_PUBLIC_WORLD_PRESET === "device" ? "device" : "orb";
// "staging" = World App simulator (simulator.worldcoin.org), no phone or Orb needed. "production" = real World App.
export const WORLD_ENV = process.env.NEXT_PUBLIC_WORLD_ENV === "production" ? "production" : "staging";

export const NETWORK = process.env.NEXT_PUBLIC_NEAR_NETWORK === "mainnet" ? "mainnet" : "testnet";
export const VAULT_ID = process.env.NEXT_PUBLIC_NEAR_CONTRACT_ID ?? "";
// rpc.testnet.near.org is deprecated and answers 429 to everything; these answered vault views on 2026-11-12
export const RPC_URLS = (process.env.NEXT_PUBLIC_NEAR_RPC_URL ?? "").split(",").map((u) => u.trim()).filter(Boolean);
if (!RPC_URLS.length) RPC_URLS.push(...(NETWORK === "mainnet" ? ["https://rpc.mainnet.fastnear.com"] : ["https://test.rpc.fastnear.com", "https://near-testnet.drpc.org"]));
export const EXPLORER = NETWORK === "mainnet" ? "https://nearblocks.io" : "https://testnet.nearblocks.io";

export const txLink = (hash: string) => `${EXPLORER}/txns/${hash}`;
export const addressLink = (account: string) => `${EXPLORER}/address/${account}`;

/**
 * One fixed date format in the viewer's timezone, e.g. "Thu 13 Nov, 22:07 GMT+5:30". Browser only: the server's
 * clock and timezone differ from the viewer's, so calling this during server rendering breaks hydration.
 */
export const formatWhen = (ms: number, timeZone?: string) =>
  new Intl.DateTimeFormat("en-GB", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZoneName: "short", timeZone }).format(ms);

const YOCTO = 10n ** 24n;
/** yoctoNEAR to a plain decimal string ("0.0005"), exact, trailing zeros dropped. */
export function formatNear(yocto: bigint) {
  const neg = yocto < 0n, v = neg ? -yocto : yocto;
  const frac = (v % YOCTO).toString().padStart(24, "0").replace(/0+$/, "");
  return `${neg ? "-" : ""}${v / YOCTO}${frac ? `.${frac}` : ""}`;
}
/** "0.5" NEAR to yoctoNEAR; throws on anything that isn't a plain non-negative decimal with at most 24 places. */
export function parseNear(s: string) {
  const m = s.trim().match(/^(\d+)(?:\.(\d{1,24}))?$/);
  if (!m) throw new Error(`"${s}" is not an amount in NEAR`);
  return BigInt(m[1]) * YOCTO + BigInt((m[2] ?? "").padEnd(24, "0"));
}
