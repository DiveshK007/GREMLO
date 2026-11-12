import { test } from "node:test";
import assert from "node:assert/strict";
import { broadcastOnce, failover, isRetryable, parseUrls, viewCache } from "./rpc.ts";

const rateLimited = () => Object.assign(new Error("HTTP 429 Too Many Requests"), { status: 429 });
const timedOut = () => Object.assign(new TypeError("fetch failed"), { cause: Object.assign(new Error("connect ETIMEDOUT 1.2.3.4:443"), { code: "ETIMEDOUT" }) });
const noWait = async () => {};

test("parseUrls: comma list, whitespace, empty means the defaults", () => {
  assert.deepEqual(parseUrls(" https://a , https://b,", ["d"]), ["https://a", "https://b"]);
  assert.deepEqual(parseUrls("", ["d"]), ["d"]);
  assert.deepEqual(parseUrls(undefined, ["d"]), ["d"]);
});

test("view cache: N concurrent callers share one in-flight read, then the result lives for the TTL", async () => {
  let t = 0, loads = 0;
  const cache = viewCache(5000, () => t);
  let release!: (v: number) => void;
  const load = () => (loads++, new Promise<number>((r) => (release = r)));
  const many = Array.from({ length: 20 }, () => cache.get("get_pet:mochi", load));
  release(7);
  assert.deepEqual(await Promise.all(many), Array(20).fill(7));
  assert.equal(loads, 1, "20 pollers, 1 RPC call");
  t = 4999;
  assert.equal(await cache.get("get_pet:mochi", async () => (loads++, 8)), 7);
  t = 5000;
  assert.equal(await cache.get("get_pet:mochi", async () => (loads++, 8)), 8, "expired after 5 s");
  assert.equal(await cache.get("campaign_count", async () => (loads++, 1)), 1, "keys are separate");
  assert.equal(loads, 3);
  cache.clear();
  assert.equal(await cache.get("get_pet:mochi", async () => (loads++, 9)), 9, "a write clears it");
});

test("view cache: a failure is shared by the callers waiting on it, but never cached", async () => {
  const cache = viewCache(5000, () => 0);
  let loads = 0;
  const fail = () => (loads++, Promise.reject(rateLimited()));
  const r = await Promise.allSettled([cache.get("k", fail), cache.get("k", fail)]);
  assert.deepEqual(r.map((x) => x.status), ["rejected", "rejected"]);
  assert.equal(loads, 1);
  assert.equal(await cache.get("k", async () => (loads++, "ok")), "ok");
  assert.equal(loads, 2);
});

test("isRetryable: rate limits, timeouts and 5xx yes; contract errors and missing accounts no", () => {
  for (const e of [rateLimited(), timedOut(), new Error("HTTP 503 Service Unavailable"), new Error("TimeoutError: The operation was aborted due to timeout")]) assert.equal(isRetryable(e), true, String(e));
  for (const e of [new Error("Smart contract panicked: OverBudget"), new Error("account mochi.testnet does not exist while viewing"), new Error("InvalidNonce")]) assert.equal(isRetryable(e), false, String(e));
});

test("failover: 429 on the first RPC moves to the next with backoff, and the one that answered stays preferred", async () => {
  const waits: number[] = [], hits: string[] = [];
  const fo = failover(["https://a", "https://b"], { backoffMs: 100, wait: async (ms) => { waits.push(ms); } });
  const call = async (url: string) => { hits.push(url); if (url === "https://a") throw rateLimited(); return url; };
  assert.equal(await fo.run(call), "https://b");
  assert.deepEqual(waits, [100]);
  assert.equal(fo.current, "https://b");
  assert.equal(await fo.run(call), "https://b");
  assert.deepEqual(hits, ["https://a", "https://b", "https://b"], "the next call goes straight to b");
});

test("failover: a contract error is thrown at once; all RPCs failing throws the last error", async () => {
  const fo = failover(["a", "b"], { wait: noWait });
  let calls = 0;
  await assert.rejects(fo.run(async () => { calls++; throw new Error("Smart contract panicked: UnknownPet"); }), /UnknownPet/);
  assert.equal(calls, 1);
  await assert.rejects(fo.run(async (u) => { throw u === "a" ? rateLimited() : timedOut(); }), (e: any) => /fetch failed/.test(e.message) && e.rpcUrl === "b");
});

test("broadcastOnce: a send that timed out but landed is found by hash and never sent again", async () => {
  const sent: string[] = [], asked: string[] = [];
  const r = await broadcastOnce(["a", "b"], {
    wait: noWait,
    send: async (url) => { sent.push(url); throw timedOut(); },
    status: async (url) => { asked.push(url); return { hash: "H", via: url }; },
  });
  assert.deepEqual(r, { hash: "H", via: "b" });
  assert.deepEqual(sent, ["a"], "sent once");
  assert.deepEqual(asked, ["b"]);
});

test("broadcastOnce: unknown to the next RPC, the same signed tx is sent there; a contract failure is not retried", async () => {
  const sent: string[] = [];
  const r = await broadcastOnce(["a", "b"], {
    wait: noWait,
    send: async (url) => { sent.push(url); if (url === "a") throw rateLimited(); return { ok: url }; },
    status: async () => null,
  });
  assert.deepEqual(r, { ok: "b" });
  assert.deepEqual(sent, ["a", "b"]);
  let tries = 0;
  await assert.rejects(broadcastOnce(["a", "b"], { wait: noWait, send: async () => { tries++; throw new Error("Smart contract panicked: OverBudget"); }, status: async () => null }), /OverBudget/);
  assert.equal(tries, 1);
});
