import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { BaseError, getAddress, isAddress } from "viem";
import { signRequest } from "@worldcoin/idkit-core/signing";
import { abi, chain, deployBlock, pub, seeded, send, vault } from "./chain.ts";
import { planSettlement, type Pending } from "./batch.ts";
import { campaignView, petView } from "./views.ts";
import { bad, HttpError, makeRegister, verifyWorldProof, WORLD_ACTIONS, type PetRecord } from "./register.ts";
import { addThought, type Thought } from "./thoughts.ts";
// @ts-expect-error plain ESM JS package, no types
import { think } from "../../../packages/brain/index.js";

type Store = {
  pets: Record<string, PetRecord>; // keyed by name
  nullifiers: string[];
  pending: Record<string, Pending>; // campaign id -> pet key -> count
  lines: Record<string, string>; // lineHash -> ad line text (the chain only stores the hash)
  brands: Record<string, string>; // brand address -> display name
  today: Record<string, { day: string; count: number }>; // pet key -> impressions accepted today (UTC)
  thoughts: Record<string, Thought[]>; // pet key -> last 0G decisions with request IDs
};

// shortcut: one JSON file, single process; move to DATABASE_URL if the server ever runs twice
const STORE_FILE = new URL("../data.json", import.meta.url);
const store: Store = {
  pets: {}, nullifiers: [], pending: {}, lines: {}, brands: {}, today: {}, thoughts: {},
  ...(existsSync(STORE_FILE) ? JSON.parse(readFileSync(STORE_FILE, "utf8")) : {}),
};
const utcDay = () => new Date().toISOString().slice(0, 10);
const save = () => writeFileSync(STORE_FILE, JSON.stringify(store, null, 2));

const MAX_COUNT = 1000; // per impression entry; the Mac app rate-limits far below this
const settling = new Set<string>(); // campaigns with a settlement in flight

const RP_ID = process.env.RP_ID;
const RP_SIGNING_KEY = process.env.RP_SIGNING_KEY;
if (!RP_ID || !RP_SIGNING_KEY) throw new Error("missing env RP_ID or RP_SIGNING_KEY");

const wei = (name: string) => {
  const v = process.env[name];
  if (!v || !/^[0-9]+$/.test(v)) throw new Error(`missing or non-integer env ${name} (wei)`);
  return BigInt(v);
};
const thresholds = { thriving: wei("MOOD_THRIVING_WEI"), stable: wei("MOOD_STABLE_WEI"), hungry: wei("MOOD_HUNGRY_WEI") };

// Every hook event reads the pet; 30s keeps a tool burst from hammering the RPC. Only successes are cached.
const balanceCache = new Map<string, { at: number; wei: bigint }>();
async function payoutBalance(payout: `0x${string}`) {
  const hit = balanceCache.get(payout);
  if (hit && Date.now() - hit.at < 30_000) return hit.wei;
  try {
    const w = await pub.getBalance({ address: payout });
    balanceCache.set(payout, { at: Date.now(), wei: w });
    return w;
  } catch (e) {
    console.error(`balance read failed: ${errMsg(e)}`);
    return null;
  }
}

const registerPet = makeRegister({
  verify: (result) => verifyWorldProof(result, RP_ID),
  registerOnChain: (pet, owner, payout) => send("registerPet", [pet, owner, payout]),
  store,
  save,
  seeded,
});

/** RP signature for an IDKit request. The signing key stays here; only the signature leaves. */
function worldSign(action: string | null) {
  if (!action || !WORLD_ACTIONS.has(action)) throw bad("unknown action");
  const s = signRequest({ action, signingKeyHex: RP_SIGNING_KEY! });
  return { sig: s.sig, nonce: s.nonce, created_at: s.createdAt, expires_at: s.expiresAt };
}

const errMsg = (e: unknown) => (e instanceof BaseError ? e.shortMessage : e instanceof Error ? e.message : String(e));
const findPet = (key: string) =>
  store.pets[key] ?? Object.values(store.pets).find((p) => p.petKey.toLowerCase() === key.toLowerCase());

async function readBody(req: IncomingMessage) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 100_000) throw new HttpError(413, "body too large");
  }
  try { return raw ? JSON.parse(raw) : {}; } catch { throw bad("invalid JSON"); }
}

function addImpressions(body: any) {
  if (!Array.isArray(body.impressions) || body.impressions.length === 0) throw bad("impressions must be a non-empty array");
  // validate all entries before touching the store so a bad batch changes nothing
  const rows = body.impressions.map((i: any) => {
    const pet = findPet(String(i?.petKey ?? ""));
    if (!pet) throw bad(`unknown pet ${i?.petKey}`);
    const id = String(i.campaignId);
    if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaignId must be a positive integer");
    if (!Number.isInteger(i.count) || i.count < 1 || i.count > MAX_COUNT) throw bad(`count must be 1..${MAX_COUNT}`);
    return { id, petKey: pet.petKey, count: i.count as number };
  });
  for (const r of rows) {
    const p = (store.pending[r.id] ??= {});
    p[r.petKey] = (p[r.petKey] ?? 0) + r.count;
    const t = store.today[r.petKey];
    store.today[r.petKey] = { day: utcDay(), count: (t?.day === utcDay() ? t.count : 0) + r.count };
  }
  save();
  return { accepted: rows.length, pending: store.pending };
}

async function settle(id: string) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  if (settling.has(id)) throw new HttpError(409, "settlement already running for this campaign");
  settling.add(id);
  try {
    const [, , , rate] = await pub.readContract({ address: vault, abi, functionName: "campaigns", args: [BigInt(id)] });
    if (rate === 0n) throw new HttpError(404, "unknown campaign");
    const remaining = await pub.readContract({ address: vault, abi, functionName: "remaining", args: [BigInt(id)] });
    const plan = planSettlement(store.pending[id] ?? {}, rate, remaining);

    const settled = [];
    let error: string | undefined;
    for (const s of plan.settle) {
      try {
        const txHash = await send("settleImpressions", [BigInt(id), s.pet, BigInt(s.count)]);
        // deduct only what was paid, one pet at a time, so a failure mid-batch loses nothing
        store.pending[id][s.pet] -= s.count;
        if (store.pending[id][s.pet] === 0) delete store.pending[id][s.pet];
        save();
        settled.push({ petKey: s.pet, count: s.count, amount: s.amount.toString(), txHash });
      } catch (e) {
        error = errMsg(e);
        break;
      }
    }
    return { campaignId: id, settled, pending: store.pending[id] ?? {}, error, seeded };
  } finally {
    settling.delete(id);
  }
}

/** The campaign the pet shows: the first live one that can still pay for an impression, or null. */
async function activeCampaign() {
  const [created, block] = await Promise.all([
    pub.getContractEvents({ address: vault, abi, eventName: "CampaignCreated", fromBlock: deployBlock }),
    pub.getBlock(),
  ]);
  for (const ev of created) {
    const id = ev.args.id!;
    const [brand, budget, spent, rate, endTime, closed, lineHash] = await pub.readContract({
      address: vault, abi, functionName: "campaigns", args: [id],
    });
    if (closed || endTime <= block.timestamp || budget - spent < rate) continue;
    return campaignView({ id, brand, lineHash, rate }, store);
  }
  return null;
}

async function getPet(key: string) {
  const rec = findPet(key);
  if (!rec && !isAddress(key)) throw new HttpError(404, "unknown pet");
  const petKey = getAddress(rec?.petKey ?? key);
  let payout = rec?.payout;
  try {
    const [owner, p] = await pub.readContract({ address: vault, abi, functionName: "pets", args: [petKey] });
    if (owner === "0x0000000000000000000000000000000000000000") throw new HttpError(404, "pet not registered onchain");
    payout = p;
  } catch (e) {
    if (e instanceof HttpError || !rec) throw e; // RPC down: a pet we registered still answers, asleep
  }
  const t = store.today[petKey];
  return petView({
    name: rec?.name ?? petKey.toLowerCase(),
    walletBalance: await payoutBalance(getAddress(payout!)), // payout is where the pet's earnings land
    thresholds,
    impressionsToday: t?.day === utcDay() ? t.count : 0,
    seeded,
    lastThoughts: store.thoughts[petKey],
  });
}

const str = (v: unknown) => (typeof v === "string" ? v.slice(0, 64) : undefined);

/** One pet decision from a Claude Code hook. A sleep is a valid answer, so it is 200 too. */
async function petThink(key: string, body: any) {
  const event = str(body.event);
  if (!event) throw bad("event is required");
  const pet = await getPet(key); // 404s for unknown pets; mood comes from the same place as GET /pets/:name
  const r = await think({ event, mood: pet.mood, toolName: str(body.toolName), notificationType: str(body.notificationType) });
  const petKey = getAddress(findPet(key)?.petKey ?? key);
  store.thoughts[petKey] = addThought(store.thoughts[petKey], r);
  save();
  return r;
}

async function route(req: IncomingMessage) {
  const { pathname, searchParams } = new URL(req.url ?? "/", "http://x");
  const m = req.method;
  if (m === "GET" && pathname === "/world/sign") return worldSign(searchParams.get("action"));
  if (m === "POST" && pathname === "/pets/register") return registerPet(await readBody(req));
  if (m === "POST" && pathname === "/impressions") return addImpressions(await readBody(req));
  if (m === "POST" && pathname.startsWith("/settle/")) return settle(pathname.slice(8));
  if (m === "GET" && pathname === "/campaigns/active") return activeCampaign();
  const thinkPath = pathname.match(/^\/pets\/([^/]+)\/think$/);
  if (m === "POST" && thinkPath) return petThink(decodeURIComponent(thinkPath[1]), await readBody(req));
  if (m === "GET" && pathname.startsWith("/pets/")) return getPet(decodeURIComponent(pathname.slice(6)));
  throw new HttpError(404, "not found");
}

const reply = (res: ServerResponse, status: number, body: unknown) => {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};

const port = Number(process.env.PORT ?? 8787);
createServer((req, res) => {
  route(req).then(
    (body) => reply(res, 200, body),
    (e) => {
      const status = e instanceof HttpError ? e.status : 502; // anything else is the chain or RPC failing
      if (status === 502) console.error(errMsg(e));
      reply(res, status, { error: errMsg(e) });
    },
  );
}).listen(port, () => console.log(`server on :${port}, vault ${vault}, chain ${chain.id}`));
