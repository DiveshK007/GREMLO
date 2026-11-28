// npm run verify:public (testnet) / verify:public:mainnet: checks a published proof against public NEAR RPC and the
// live API. No API key, no .env. --fixture <path> picks the run. Exit 0 if every check passes, 1 if any fails.
import { readFileSync } from "node:fs";

// what: the method called, or "deploy" for a deploy (+ init) of the vault. completionId: must be in the tx's events.
type Tx = { step: number; what: string; signer: string; hash: string; completionId?: string };
const fixtureArg = process.argv.indexOf("--fixture");
const fixturePath = fixtureArg > 0 ? new URL(process.argv[fixtureArg + 1], `file://${process.cwd()}/`) : new URL("../fixtures/public-proof.json", import.meta.url);
const fx = JSON.parse(readFileSync(fixturePath, "utf8")) as {
  vault: string; codeHash: string; rpc: string[]; rpcLive?: string[]; api: string; network: string; minPaidYocto: string; minComputeChargedYocto: string; txs: Tx[];
};
const live = [...(fx.rpcLive ?? ["https://test.rpc.fastnear.com"]), ...fx.rpc]; // current state; fx.rpc is archival, for old txs
console.log(`${fx.network}: ${fx.vault}, ${fx.txs.length} transactions`);
const api = (process.env.GREMLO_API || fx.api).replace(/\/$/, "");

async function rpc(method: string, params: unknown, urls = fx.rpc) {
  let last = "no RPC answered";
  for (const u of urls) {
    try {
      const r = await fetch(u, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }), signal: AbortSignal.timeout(20_000) });
      const j = (await r.json()) as { result?: any; error?: any }; // eslint-disable-line @typescript-eslint/no-explicit-any -- RPC JSON, read field by field below
      if (j.result) return j.result;
      last = `${u}: ${JSON.stringify(j.error?.cause?.name ?? j.error?.message ?? j.error)}`;
    } catch (e) {
      last = `${u}: ${(e as Error).message}`;
    }
  }
  throw new Error(last);
}

let failed = 0;
const check = (ok: boolean, line: string) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${line}`);
  if (!ok) failed++;
};
const near = (y: bigint) => `${Number(y / 10n ** 20n) / 1e4} NEAR`; // display only

// 1. every tx in the final run succeeded, on the vault, by the expected signer and method
for (const t of fx.txs) {
  try {
    const r = await rpc("EXPERIMENTAL_tx_status", { tx_hash: t.hash, sender_account_id: t.signer, wait_until: "FINAL" });
    const tx = r.transaction;
    const kinds = tx.actions.map((a: object) => (typeof a === "string" ? a : Object.keys(a)[0]));
    const method = tx.actions.find((a: { FunctionCall?: object }) => typeof a === "object" && a.FunctionCall)?.FunctionCall?.method_name;
    const did = t.what === "deploy" ? kinds.includes("DeployContract") : method === t.what;
    const failedReceipt = r.receipts_outcome.some((o: { outcome: { status: object } }) => "Failure" in o.outcome.status);
    const logs: string[] = r.receipts_outcome.flatMap((o: { outcome: { logs: string[] } }) => o.outcome.logs);
    const carries = !t.completionId || logs.some((l) => l.includes(`"near_ai_completion_id":"${t.completionId}"`));
    check("SuccessValue" in r.status && !failedReceipt && tx.receiver_id === fx.vault && tx.signer_id === t.signer && did && carries,
      `tx ${t.step} ${t.what} ${t.hash.slice(0, 8)}...${t.completionId ? ` carries ${t.completionId.slice(0, 18)}...` : ""}`);
  } catch (e) {
    check(false, `tx ${t.step} ${t.what} ${t.hash.slice(0, 8)}...: ${(e as Error).message}`);
  }
}

// 2. the vault's deployed code is the code that ran
try {
  const a = await rpc("query", { request_type: "view_account", finality: "final", account_id: fx.vault }, live);
  check(a.code_hash === fx.codeHash, `code hash ${a.code_hash}${a.code_hash === fx.codeHash ? "" : ` (expected ${fx.codeHash})`}`);
} catch (e) {
  check(false, `code hash: ${(e as Error).message}`);
}

// 3. /stats agrees with the vault. /stats is cached for a minute, so it may lag the chain but never lead it.
try {
  const s = (await (await fetch(`${api}/stats`, { signal: AbortSignal.timeout(15_000) })).json()) as Record<string, string | boolean | number>;
  const v = await rpc("query", { request_type: "call_function", finality: "final", account_id: fx.vault, method_name: "get_totals", args_base64: "e30=" }, live);
  const t = JSON.parse(Buffer.from(v.result).toString()) as Record<"total_deposited" | "paid_to_pets" | "compute_budgets" | "compute_charged" | "remaining" | "refunded", string>;
  const out = (["paid_to_pets", "compute_budgets", "compute_charged", "remaining", "refunded"] as const).reduce((a, k) => a + BigInt(t[k]), 0n);
  check(out === BigInt(t.total_deposited), `the vault's books balance: paid + budgets + charged + remaining + refunded = deposited (${near(BigInt(t.total_deposited))})`);
  const chainPaid = BigInt(t.paid_to_pets) + BigInt(t.compute_budgets) + BigInt(t.compute_charged);
  const paid = BigInt(s.paidWei as string), charged = BigInt(s.computeChargedWei as string);
  check(s.vault === fx.vault && s.network === fx.network && s.seeded === false, `/stats names ${s.vault} on ${s.network}, seeded=${s.seeded}`);
  check(paid >= BigInt(fx.minPaidYocto) && paid <= chainPaid, `/stats paid ${near(paid)} is between the final run (${near(BigInt(fx.minPaidYocto))}) and the vault's total (${near(chainPaid)})`);
  check(charged >= BigInt(fx.minComputeChargedYocto) && charged <= BigInt(t.compute_charged), `/stats compute charged ${near(charged)} is within the vault's ${near(BigInt(t.compute_charged))}`);
  check(Number(s.campaigns) >= 1, `/stats campaigns ${s.campaigns}`);
} catch (e) {
  check(false, `/stats: ${(e as Error).message}`);
}

console.log(failed ? `${failed} check(s) failed` : "All checks passed");
process.exit(failed ? 1 : 0);
