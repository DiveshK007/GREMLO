// NEAR access for the browser: views over plain JSON-RPC, signing through NEAR Connect (the brand's or owner's wallet).
import { keccak256, toHex } from "viem";
import { NETWORK, RPC_URLS, VAULT_ID } from "./config";

/** A vault view over JSON-RPC; returns the parsed JSON result. A 429, 5xx or network error moves to the next RPC URL. */
export async function view<T>(method: string, args: Record<string, unknown> = {}): Promise<T> {
  const body = JSON.stringify({
    jsonrpc: "2.0", id: "view", method: "query",
    params: { request_type: "call_function", finality: "final", account_id: VAULT_ID, method_name: method, args_base64: btoa(JSON.stringify(args)) },
  });
  let last = "";
  for (const [k, url] of RPC_URLS.entries()) {
    if (k > 0) await new Promise((r) => setTimeout(r, 400 * 2 ** (k - 1)));
    let j: any;
    try {
      const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body });
      if (res.status === 429 || res.status >= 500) { last = `${new URL(url).host} HTTP ${res.status}`; continue; }
      j = await res.json();
    } catch (e) {
      last = `${new URL(url).host}: ${(e as Error).message}`;
      continue;
    }
    if (j.error?.code === -429) { last = `${new URL(url).host} rate limited`; continue; }
    if (j.error || j.result?.error) throw new Error(`NEAR view ${method} failed: ${JSON.stringify(j.error ?? j.result.error).slice(0, 200)}`);
    return JSON.parse(new TextDecoder().decode(new Uint8Array(j.result.result)));
  }
  throw new Error(`NEAR view ${method}: every RPC failed (last: ${last})`);
}

/** keccak256 of the hook lines, 0x-prefixed (the server checks it; the vault stores it without 0x). */
export const lineHash = (line: string) => keccak256(toHex(line));

let connector: Promise<any> | null = null;
const near = () => (connector ??= import("@hot-labs/near-connect").then(({ NearConnector }) => new NearConnector({ network: NETWORK })));

/** Opens the wallet picker (or reuses the connected wallet) and returns the NEAR account id. */
export async function connectWallet(): Promise<string> {
  const c = await near();
  let wallet = await c.wallet().catch(() => null);
  if (!wallet) wallet = await c.connect();
  const [account] = await wallet.getAccounts();
  if (!account?.accountId) throw new Error("The wallet returned no account.");
  return account.accountId;
}

/** One vault call signed by the connected wallet; returns the tx hash and the decoded return value. */
async function call(account: string, methodName: string, args: object, deposit: bigint) {
  const wallet = await (await near()).wallet();
  const r: any = await wallet.signAndSendTransaction({
    signerId: account, receiverId: VAULT_ID,
    actions: [{ type: "FunctionCall", params: { methodName, args, gas: "100000000000000", deposit: deposit.toString() } }],
  });
  const hash: string = r?.transaction?.hash ?? r?.transaction_outcome?.id;
  const failure = r?.status?.Failure;
  if (failure) throw new Error(`Transaction ${hash} failed: ${JSON.stringify(failure).match(/Smart contract panicked: ([^"\\]+)/)?.[1] ?? JSON.stringify(failure).slice(0, 200)}`);
  const ok = r?.status?.SuccessValue;
  return { txHash: hash, value: ok ? JSON.parse(atob(ok)) : null };
}

type Campaign = { brand: string; budget: string; spent: string; rate: string; end_time: number; closed: boolean; line_hash: string };

export async function createCampaign(opts: { account: string; line: string; budgetWei: bigint; rateWei: bigint; endTime: bigint }) {
  if (!VAULT_ID) throw new Error("NEXT_PUBLIC_NEAR_CONTRACT_ID is not set.");
  const r = await call(opts.account, "create_campaign", { line_hash: lineHash(opts.line).slice(2), rate: opts.rateWei.toString(), end_time: Number(opts.endTime) }, opts.budgetWei);
  if (typeof r.value !== "number") throw new Error(`Transaction ${r.txHash} succeeded but returned no campaign id.`);
  return { txHash: r.txHash, campaignId: BigInt(r.value) };
}

export async function readCampaign(id: bigint) {
  const c = await view<Campaign | null>("get_campaign", { id: Number(id) });
  if (!c) throw new Error(`No campaign #${id} on ${VAULT_ID}.`);
  const remaining = await view<string>("remaining", { id: Number(id) });
  return {
    brand: c.brand, budget: BigInt(c.budget), spent: BigInt(c.spent), rate: BigInt(c.rate), endTime: BigInt(c.end_time),
    closed: c.closed, lineHash: `0x${c.line_hash}`, remaining: BigInt(remaining),
  };
}

/** Adds budget to a running campaign. Only the brand that created it can, and only before it ends (the vault checks). */
export async function topUpCampaign(account: string, id: bigint, valueWei: bigint) {
  return (await call(account, "top_up", { id: Number(id) }, valueWei)).txHash;
}

/** Closes an ended campaign; the vault refunds the remainder to the brand. */
export async function closeCampaign(account: string, id: bigint) {
  const refund = BigInt(await view<string>("remaining", { id: Number(id) }));
  return { txHash: (await call(account, "close", { id: Number(id) }, 0n)).txHash, refund };
}

/** NEP-413: the owner's wallet signs `message` for the vault as recipient, with a fresh 32-byte nonce. */
export async function signOwnerMessage(account: string, message: string) {
  const nonce = crypto.getRandomValues(new Uint8Array(32));
  const s = await (await near()).wallet().then((w: any) => w.signMessage({ message, recipient: VAULT_ID, nonce, signerId: account }));
  return { signature: s.signature as string, publicKey: s.publicKey as string, nonce: btoa(String.fromCharCode(...nonce)), accountId: s.accountId as string };
}
