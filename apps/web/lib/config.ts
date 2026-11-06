import { defineChain, type Address } from "viem";

export const SERVER_URL = process.env.NEXT_PUBLIC_SERVER_URL ?? "http://localhost:8787";
export const WORLD_APP_ID = process.env.NEXT_PUBLIC_WORLD_APP_ID ?? "";
export const WORLD_RP_ID = process.env.NEXT_PUBLIC_WORLD_RP_ID ?? "";
export const WORLD_PRESET = process.env.NEXT_PUBLIC_WORLD_PRESET === "device" ? "device" : "orb";

export const CHAIN_ID = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 16602);
export const CHAIN_RPC = process.env.NEXT_PUBLIC_CHAIN_RPC ?? "https://evmrpc-testnet.0g.ai";
export const EXPLORER = process.env.NEXT_PUBLIC_EXPLORER ?? "https://chainscan-galileo.0g.ai";
export const VAULT_ADDRESS = (process.env.NEXT_PUBLIC_VAULT_ADDRESS ?? "") as Address;

export const galileo = defineChain({
  id: CHAIN_ID,
  name: CHAIN_ID === 16602 ? "0G Galileo Testnet" : `Chain ${CHAIN_ID}`,
  nativeCurrency: { name: "0G", symbol: "0G", decimals: 18 },
  rpcUrls: { default: { http: [CHAIN_RPC] } },
  blockExplorers: { default: { name: "Chainscan", url: EXPLORER } },
});

export const txLink = (hash: string) => `${EXPLORER}/tx/${hash}`;
export const addressLink = (addr: string) => `${EXPLORER}/address/${addr}`;
