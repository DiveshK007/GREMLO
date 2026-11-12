import { Account, JsonRpcProvider } from "near-api-js";
import { errText } from "./register.ts";

// NEAR testnet access for the vault (contracts-near). Views go through RPC; changes are signed by the operator,
// whose key comes from env and is never logged. One operator tx at a time, so access-key nonces never collide.

const env = (k: string) => {
  const v = process.env[k];
  if (!v) throw new Error(`missing env ${k}`);
  return v;
};

export const network = process.env.NEAR_NETWORK ?? "testnet";
export const vault = env("NEAR_CONTRACT_ID");
export const operatorId = env("NEAR_OPERATOR_ACCOUNT_ID");
// || not ??: .env.example leaves NEAR_RPC_URL empty, and "" must mean the default, not a broken URL
export const rpcUrl = process.env.NEAR_RPC_URL || (network === "mainnet" ? "https://rpc.mainnet.fastnear.com" : "https://test.rpc.fastnear.com");
export const explorer = network === "mainnet" ? "https://nearblocks.io" : "https://testnet.nearblocks.io";
// a local sandbox runs on free test accounts, so everything it holds is seeded, not real money
export const seeded = network === "sandbox";

export const provider = new JsonRpcProvider({ url: rpcUrl });
const operator = new Account(operatorId, provider, env("NEAR_OPERATOR_PRIVATE_KEY") as `ed25519:${string}`);

const rpcHost = new URL(rpcUrl).host;
/** Runs one RPC call and labels any failure with the RPC host, the call and the cause. */
const rpc = <T>(what: string, run: () => Promise<T>) =>
  run().catch((e) => { throw Object.assign(new Error(`NEAR RPC ${rpcHost} ${what}: ${errText(e)}`), { cause: e }); });

/** A contract view; returns the parsed JSON result. */
export const view = <T>(method: string, args: Record<string, unknown> = {}) =>
  rpc(`view ${method}`, () => provider.callFunction({ contractId: vault, method, args }) as Promise<T>);

/** True when the account exists onchain. A missing account is false; an RPC failure throws. */
export async function accountExists(id: string) {
  try {
    await provider.viewAccount({ accountId: id });
    return true;
  } catch (e) {
    if (isMissingAccount(e)) return false;
    throw new Error(`NEAR RPC ${rpcHost} view_account ${id}: ${errText(e)}`);
  }
}
export const isMissingAccount = (e: unknown) =>
  (e as Error)?.name === "AccountDoesNotExistError" || /does not exist|UNKNOWN_ACCOUNT/i.test(String((e as Error)?.message ?? e));

/** Liquid balance in yoctoNEAR. */
export const balanceOf = async (id: string) => (await rpc(`view_account ${id}`, () => provider.viewAccount({ accountId: id }))).amount;

let queue: Promise<unknown> = Promise.resolve();
/** Sends one operator call to the vault and waits for it; throws with the contract's panic message if it fails. */
export function send(methodName: string, args: Record<string, unknown>, deposit = 0n): Promise<string> {
  const run = async () => {
    const r: any = await operator.callFunctionRaw({ contractId: vault, methodName, args, deposit, gas: 100_000_000_000_000n })
      .catch((e: Error) => { throw new Error(`NEAR RPC ${rpcHost} ${methodName} failed: ${panicOf(errText(e))}`); });
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
