// npm run verify:public: checks the published proof against NEAR testnet and the live API. No API key, no .env.
// Exit 0 if every check passes, 1 if any fails.
import { readFileSync } from "node:fs";

type Tx = { step: number; what: string; signer: string; hash: string };
const fx = JSON.parse(readFileSync(new URL("../fixtures/public-proof.json", import.meta.url), "utf8")) as {
  vault: string; codeHash: string; rpc: string[]; api: string; network: string; minPaidYocto: string; minComputeChargedYocto: string; txs: Tx[];
};
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
    const method = tx.actions[0]?.FunctionCall?.method_name;
    const failedReceipt = r.receipts_outcome.some((o: { outcome: { status: object } }) => "Failure" in o.outcome.status);
    check("SuccessValue" in r.status && !failedReceipt && tx.receiver_id === fx.vault && tx.signer_id === t.signer && method === t.what, `tx ${t.step} ${t.what} ${t.hash.slice(0, 8)}...`);
  } catch (e) {
    check(false, `tx ${t.step} ${t.what} ${t.hash.slice(0, 8)}...: ${(e as Error).message}`);
  }
}

// 2. the vault's deployed code is the code that ran
try {
  const a = await rpc("query", { request_type: "view_account", finality: "final", account_id: fx.vault }, ["https://test.rpc.fastnear.com", ...fx.rpc]);
  check(a.code_hash === fx.codeHash, `code hash ${a.code_hash}${a.code_hash === fx.codeHash ? "" : ` (expected ${fx.codeHash})`}`);
} catch (e) {
  check(false, `code hash: ${(e as Error).message}`);
}

// 3. /stats agrees with the vault. /stats is cached for a minute, so it may lag the chain but never lead it.
try {
  const s = (await (await fetch(`${api}/stats`, { signal: AbortSignal.timeout(15_000) })).json()) as Record<string, string | boolean | number>;
  const v = await rpc("query", { request_type: "call_function", finality: "final", account_id: fx.vault, method_name: "get_totals", args_base64: "e30=" }, ["https://test.rpc.fastnear.com", ...fx.rpc]);
  const t = JSON.parse(Buffer.from(v.result).toString()) as { paid_to_pets: string; compute_budgets: string; compute_charged: string };
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
