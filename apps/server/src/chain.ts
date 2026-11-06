import { createPublicClient, createWalletClient, defineChain, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const env = (k: string) => {
  const v = process.env[k];
  if (!v) throw new Error(`missing env ${k}`);
  return v;
};

export const chain = defineChain({
  id: Number(env("ZG_CHAIN_ID")),
  name: "notchi",
  nativeCurrency: { name: "0G", symbol: "0G", decimals: 18 },
  rpcUrls: { default: { http: [env("ZG_CHAIN_RPC")] } },
});

export const vault = env("ZG_VAULT_ADDRESS") as `0x${string}`;
export const deployBlock = BigInt(env("ZG_VAULT_DEPLOY_BLOCK"));
// Anvil (31337) runs on free test accounts, so everything it holds is seeded, not real money.
export const seeded = chain.id === 31337;

export const abi = parseAbi([
  "function registerPet(address pet, address owner, address payout)",
  "function settleImpressions(uint256 id, address pet, uint256 count)",
  "function remaining(uint256 id) view returns (uint256)",
  "function campaigns(uint256) view returns (address brand, uint128 budget, uint128 spent, uint96 rate, uint64 endTime, bool closed, bytes32 lineHash)",
  "function pets(address) view returns (address owner, address payout, bool verified)",
  "event CampaignCreated(uint256 indexed id, address indexed brand, uint256 budget, uint256 rate, uint64 endTime, bytes32 lineHash)",
]);

export const pub = createPublicClient({ chain, transport: http() });
export const operator = createWalletClient({
  chain,
  transport: http(),
  account: privateKeyToAccount(env("ZG_OPERATOR_KEY") as `0x${string}`),
});

/** Send an operator tx and wait for it; throws if it reverts. */
export async function send(functionName: "registerPet" | "settleImpressions", args: readonly unknown[]) {
  const { request } = await pub.simulateContract({
    address: vault, abi, functionName, args: args as never, account: operator.account,
  });
  const hash = await operator.writeContract(request);
  const receipt = await pub.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`tx ${hash} reverted`);
  return hash;
}
