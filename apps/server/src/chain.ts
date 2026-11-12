import { createHash } from "node:crypto";
import { Account, actions, baseEncode, JsonRpcProvider, type Provider } from "near-api-js";
import { errText } from "./register.ts";
import { broadcastOnce, failover, parseUrls, viewCache, withTimeout } from "./rpc.ts";

// NEAR access for the vault (contracts-near). Views go through RPC, cached for a few seconds so many pollers cost
// one call, with failover across RPC URLs on rate limits and timeouts. Changes are signed by the operator, whose key
// comes from env and is never logged; one operator tx at a time, so access-key nonces never collide.

const env = (k: string) => {
  const v = process.env[k];
  if (!v) throw new Error(`missing env ${k}`);
  return v;
};

export const network = process.env.NEAR_NETWORK ?? "testnet";
export const vault = env("NEAR_CONTRACT_ID");
export const operatorId = env("NEAR_OPERATOR_ACCOUNT_ID");
// rpc.testnet.near.org is deprecated and answers 429 to everything; testnet-rpc.intea.rs hung on connect (10 s) in
// the live run. These two answered vault views reliably on 2026-11-12.
export const rpcUrls = parseUrls(process.env.NEAR_RPC_URL, network === "mainnet"
  ? ["https://rpc.mainnet.fastnear.com"]
  : ["https://test.rpc.fastnear.com", "https://near-testnet.drpc.org"]);
export const explorer = network === "mainnet" ? "https://nearblocks.io" : "https://testnet.nearblocks.io";
// a local sandbox runs on free test accounts, so everything it holds is seeded, not real money
export const seeded = network === "sandbox";

// near-api-js retries 12 times by default, which turns one 429 into a burst; retry once here and fail over instead
const providers = new Map(rpcUrls.map((url) => [url, new JsonRpcProvider({ url }, { retries: 1, wait: 300, backoff: 2 })]));
const at = (url: string) => providers.get(url)!;
const fo = failover(rpcUrls);
const host = (url: string) => new URL(url).host;

/** Every Provider method, run through the failover list (for the operator Account and NEP-413 checks). */
export const provider = new Proxy({} as Provider, {
  get: (_, method: string) => (...args: unknown[]) => fo.run((url) => (at(url) as any)[method](...args)),
});
const newOperator = () => new Account(operatorId, provider, env("NEAR_OPERATOR_PRIVATE_KEY") as `ed25519:${string}`);
let operator = newOperator();

/** Runs one RPC call with failover and labels a failure with the RPC host, the call and the cause. */
const failedAt = (e: unknown) => host((e as { rpcUrl?: string })?.rpcUrl ?? fo.current);
const rpc = <T>(what: string, run: (url: string) => Promise<T>) =>
  fo.run(run).catch((e) => { throw Object.assign(new Error(`NEAR RPC ${failedAt(e)} ${what}: ${errText(e)}`), { cause: e }); });

const views = viewCache(5_000);
/** A contract view; returns the parsed JSON result. Cached 5 s; identical reads in flight share one call. */
export const view = <T>(method: string, args: Record<string, unknown> = {}) =>
  views.get(`${method}:${JSON.stringify(args)}`, () => rpc(`view ${method}`, (url) => at(url).callFunction({ contractId: vault, method, args }) as Promise<T>));

/** True when the account exists onchain. A missing account is false; an RPC failure throws. */
export async function accountExists(id: string) {
  try {
    await fo.run((url) => at(url).viewAccount({ accountId: id }));
    return true;
  } catch (e) {
    if (isMissingAccount(e)) return false;
    throw new Error(`NEAR RPC ${failedAt(e)} view_account ${id}: ${errText(e)}`);
  }
}
export const isMissingAccount = (e: unknown) =>
  (e as Error)?.name === "AccountDoesNotExistError" || /does not exist|UNKNOWN_ACCOUNT/i.test(String((e as Error)?.message ?? e));

/** Liquid balance in yoctoNEAR. */
export const balanceOf = async (id: string) => (await rpc(`view_account ${id}`, (url) => at(url).viewAccount({ accountId: id }))).amount;

const unknownTx = (e: unknown) => (e as Error)?.name === "UnknownTransactionError" || /UNKNOWN_TRANSACTION|doesn't exist|does not exist|not found/i.test(errText(e));

let queue: Promise<unknown> = Promise.resolve();
/**
 * Sends one operator call to the vault and waits for it; throws with the contract's panic message if it fails.
 * The tx is signed once; on a 429 or timeout the next RPC is asked for it by hash before the same bytes are resent.
 */
export function send(methodName: string, args: Record<string, unknown>, deposit = 0n): Promise<string> {
  const attempt = async () => {
    const signed = await operator.createSignedTransaction({ receiverId: vault, actions: [actions.functionCall(methodName, args, 100_000_000_000_000n, deposit)] });
    const hash = baseEncode(createHash("sha256").update(signed.transaction.encode()).digest());
    // a send waits for execution, so it gets 30 s; a status check is a plain read and gets the usual 3 s
    return broadcastOnce<any>(fo.order(), {
      send: (url) => withTimeout(at(url).sendTransactionUntil(signed, "EXECUTED_OPTIMISTIC"), 30_000),
      status: (url) => withTimeout(at(url).viewTransactionStatus({ txHash: hash, accountId: operatorId, waitUntil: "EXECUTED_OPTIMISTIC" }), 3_000).catch((e) => { if (unknownTx(e)) return null; throw e; }),
      ok: fo.ok,
      fail: fo.fail,
    });
  };
  const run = async () => {
    let r: any;
    try {
      r = await attempt();
    } catch (e) {
      // a stale cached nonce (another signer used the key): start from the chain's nonce and try once more
      if (!/InvalidNonce/i.test(errText(e))) throw new Error(`NEAR RPC ${failedAt(e)} ${methodName} failed: ${panicOf(errText(e))}`);
      operator = newOperator();
      r = await attempt().catch((e2) => { throw new Error(`NEAR RPC ${failedAt(e2)} ${methodName} failed: ${panicOf(errText(e2))}`); });
    }
    views.clear(); // the next read sees this write
    const hash: string = r?.transaction?.hash ?? r?.transaction_outcome?.id;
    const failure = r?.status?.Failure ?? r?.receipts_outcome?.find((o: any) => o?.outcome?.status?.Failure)?.outcome?.status?.Failure;
    if (failure) throw Object.assign(new Error(`tx ${hash} failed: ${panicOf(failure)}`), { txHash: hash });
    return hash;
  };
  const p = queue.then(run, run);
  queue = p.catch(() => undefined);
  return p;
}

/** The contract's own message ("OverBudget", "PetNotVerified", ...) from a NEAR failure, else the raw JSON. */
export function panicOf(failure: unknown): string {
  const s = typeof failure === "string" ? failure : JSON.stringify(failure);
  return s.match(/Smart contract panicked: ([^"\\]+)/)?.[1] ?? s.slice(0, 300);
}
