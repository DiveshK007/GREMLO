"use client";

import {
  createPublicClient,
  createWalletClient,
  custom,
  formatEther,
  http,
  keccak256,
  parseEventLogs,
  toHex,
  type Address,
  type Hash,
} from "viem";
import { galileo, VAULT_ADDRESS } from "./config";

export const vaultAbi = [
  {
    type: "function",
    name: "createCampaign",
    stateMutability: "payable",
    inputs: [
      { name: "lineHash", type: "bytes32" },
      { name: "rate", type: "uint96" },
      { name: "endTime", type: "uint64" },
    ],
    outputs: [{ name: "id", type: "uint256" }],
  },
  {
    type: "function",
    name: "close",
    stateMutability: "nonpayable",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [],
  },
  {
    type: "function",
    name: "remaining",
    stateMutability: "view",
    inputs: [{ name: "id", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "campaigns",
    stateMutability: "view",
    inputs: [{ name: "", type: "uint256" }],
    outputs: [
      { name: "brand", type: "address" },
      { name: "budget", type: "uint128" },
      { name: "spent", type: "uint128" },
      { name: "rate", type: "uint96" },
      { name: "endTime", type: "uint64" },
      { name: "closed", type: "bool" },
      { name: "lineHash", type: "bytes32" },
    ],
  },
  {
    type: "event",
    name: "CampaignCreated",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "brand", type: "address", indexed: true },
      { name: "budget", type: "uint256", indexed: false },
      { name: "rate", type: "uint256", indexed: false },
      { name: "endTime", type: "uint64", indexed: false },
      { name: "lineHash", type: "bytes32", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CampaignClosed",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "refund", type: "uint256", indexed: false },
    ],
  },
] as const;

type Eip1193 = { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> };

function injected(): Eip1193 {
  const eth = (globalThis as unknown as { ethereum?: Eip1193 }).ethereum;
  if (!eth) throw new Error("No browser wallet found. Install Core or MetaMask.");
  return eth;
}

export const publicClient = createPublicClient({ chain: galileo, transport: http() });

export function lineHash(line: string): Hash {
  return keccak256(toHex(line));
}

/** Connects the injected wallet and makes sure it is on the right chain. */
export async function connectWallet(): Promise<Address> {
  const eth = injected();
  const accounts = (await eth.request({ method: "eth_requestAccounts" })) as Address[];
  if (!accounts?.length) throw new Error("Wallet returned no account.");
  const hexId = `0x${galileo.id.toString(16)}`;
  try {
    await eth.request({ method: "wallet_switchEthereumChain", params: [{ chainId: hexId }] });
  } catch (err) {
    const code = (err as { code?: number }).code;
    if (code !== 4902) throw err;
    await eth.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: hexId,
          chainName: galileo.name,
          nativeCurrency: galileo.nativeCurrency,
          rpcUrls: galileo.rpcUrls.default.http,
          blockExplorerUrls: [galileo.blockExplorers.default.url],
        },
      ],
    });
  }
  return accounts[0];
}

function walletClient(account: Address) {
  return createWalletClient({ account, chain: galileo, transport: custom(injected()) });
}

const CREATE_GAS = 300000n; // wallets can't estimate on Galileo; a create used ~125-240k

export async function createCampaign(opts: {
  account: Address;
  line: string;
  budgetWei: bigint;
  rateWei: bigint;
  endTime: bigint;
}): Promise<{ txHash: Hash; campaignId: bigint }> {
  if (!VAULT_ADDRESS) throw new Error("NEXT_PUBLIC_VAULT_ADDRESS is not set.");
  // the wallet's "insufficient funds" surfaces as an empty revert, so check first and say what's short
  const [balance, gasPrice] = await Promise.all([publicClient.getBalance({ address: opts.account }), publicClient.getGasPrice()]);
  const fee = CREATE_GAS * gasPrice;
  if (balance < opts.budgetWei + fee) {
    throw new Error(
      `Not enough 0G: this wallet has ${formatEther(balance)} 0G, the campaign needs ${formatEther(opts.budgetWei)} 0G plus up to ${formatEther(fee)} 0G in fees. Lower the budget or use a funded wallet.`,
    );
  }
  const txHash = await walletClient(opts.account).writeContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: "createCampaign",
    args: [lineHash(opts.line), opts.rateWei, opts.endTime],
    value: opts.budgetWei,
    gas: CREATE_GAS,
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  if (receipt.status !== "success") throw new Error(`Transaction failed: ${txHash}`);
  const [created] = parseEventLogs({ abi: vaultAbi, eventName: "CampaignCreated", logs: receipt.logs });
  if (!created) throw new Error("Transaction succeeded but no CampaignCreated event was found.");
  return { txHash, campaignId: created.args.id };
}

export async function readCampaign(id: bigint) {
  const [brand, budget, spent, rate, endTime, closed, lh] = await publicClient.readContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: "campaigns",
    args: [id],
  });
  const remaining = await publicClient.readContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: "remaining",
    args: [id],
  });
  return { brand, budget, spent, rate, endTime, closed, lineHash: lh, remaining };
}

export async function closeCampaign(account: Address, id: bigint): Promise<{ txHash: Hash; refund: bigint }> {
  const txHash = await walletClient(account).writeContract({
    address: VAULT_ADDRESS,
    abi: vaultAbi,
    functionName: "close",
    args: [id],
  });
  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
  if (receipt.status !== "success") throw new Error(`Transaction failed: ${txHash}`);
  const [closed] = parseEventLogs({ abi: vaultAbi, eventName: "CampaignClosed", logs: receipt.logs });
  return { txHash, refund: closed ? closed.args.refund : 0n };
}
