import { createWalletClient, http, parseAbi, parseEther } from "viem";
import { mnemonicToAccount } from "viem/accounts";

// The pet pays for its own brain. Each pet has a wallet the server holds, derived from PET_WALLET_MNEMONIC
// (the only secret; nothing per pet is stored but its index). When the owner points the pet's payout at that
// wallet, earnings land there; the worker deposits them into the 0G Router's Payment Layer for Notchi's router
// account, and the pet's share is tracked as credit, charged per call at the cost the Router reports.
// A deterministic plan decides every deposit under a daily cap; above it the owner approves with World ID.
// The LLM never sees or moves money.

export const PAYMENT_LAYER = (process.env.ZG_PAYMENT_LAYER ?? "0x0AD9690e0b34aB2d493DE02cDF149ee34f6C9939") as `0x${string}`; // Router PL, Galileo
const ROUTER_ACCOUNT = process.env.ZG_ROUTER_ACCOUNT as `0x${string}` | undefined; // wallet behind ZG_API_KEY
const MNEMONIC = process.env.PET_WALLET_MNEMONIC;
export const feedOn = !!(MNEMONIC && ROUTER_ACCOUNT && /^0x[0-9a-fA-F]{40}$/.test(ROUTER_ACCOUNT));

export const RESERVE_WEI = parseEther(process.env.FEED_RESERVE ?? "0.002"); // left in the pet wallet for gas
export const DAILY_CAP_WEI = parseEther(process.env.FEED_DAILY_CAP ?? "0.05"); // default per pet per UTC day
export const MIN_DEPOSIT_WEI = parseEther("0.001"); // smaller deposits cost more gas than they're worth
export const LOW_CREDIT_WEI = parseEther("0.005"); // below this a capped pet asks its owner

const plAbi = parseAbi(["function depositFor(address recipient) payable", "function balanceOf(address account) view returns (uint256)"]);

export const petAccount = (index: number) => mnemonicToAccount(MNEMONIC!, { addressIndex: index });

/**
 * How much to deposit now. Everything above the gas reserve is spendable; the cap for today plus any amount the
 * owner approved bounds it. Asks for approval only when the cap holds back money and the pet is running low.
 */
export function planFeed(p: { balance: bigint; fedToday: bigint; cap: bigint; approved: bigint; credit: bigint }) {
  const spendable = p.balance > RESERVE_WEI ? p.balance - RESERVE_WEI : 0n;
  const room = p.cap + p.approved > p.fedToday ? p.cap + p.approved - p.fedToday : 0n;
  const amount = spendable < room ? spendable : room;
  const deposit = amount >= MIN_DEPOSIT_WEI ? amount : 0n;
  const held = spendable - deposit;
  return { deposit, ask: held >= MIN_DEPOSIT_WEI && p.credit + deposit < LOW_CREDIT_WEI ? held : 0n };
}

/** The Router's reported cost to wei: integers are neuron (1e18 = 1 0G); decimals are 0G. Null when absent or odd. */
export function costWei(cost: unknown): bigint | null {
  if (typeof cost === "number" && Number.isFinite(cost) && cost >= 0) cost = String(cost);
  if (typeof cost !== "string" || !cost.trim()) return null;
  const s = cost.trim();
  if (/^\d+$/.test(s)) return BigInt(s);
  if (/^\d*\.\d+$/.test(s)) return parseEther(s);
  return null;
}

/** Sends `amount` from pet wallet `index` into the Payment Layer for the router account. Returns the tx hash. */
export async function deposit(index: number, amount: bigint) {
  const { chain, pub } = await import("./chain.ts"); // loaded on use so the pure planning above tests without chain env
  const account = petAccount(index);
  const wallet = createWalletClient({ chain, transport: http(), account });
  const { request } = await pub.simulateContract({ address: PAYMENT_LAYER, abi: plAbi, functionName: "depositFor", args: [ROUTER_ACCOUNT!], value: amount, account });
  const hash = await wallet.writeContract(request);
  const receipt = await pub.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`deposit ${hash} reverted`);
  return hash;
}

/** The router account's balance in the Payment Layer, read from the chain. */
export const routerBalance = async () => (await import("./chain.ts")).pub.readContract({ address: PAYMENT_LAYER, abi: plAbi, functionName: "balanceOf", args: [ROUTER_ACCOUNT!] });
