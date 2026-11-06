import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { BaseError, getAddress, isAddress } from "viem";
import { abi, chain, deployBlock, pub, seeded, send, vault } from "./chain.ts";
import { countImpression, planSettlement, type Pending } from "./batch.ts";
import { campaignView, petView } from "./views.ts";
import { bad, HttpError, makeRegister, verifyWorldProof, type PetRecord } from "./register.ts";
import { addThought, type Thought } from "./thoughts.ts";
import { checkLine, cors, worldSign } from "./web.ts";
// @ts-expect-error plain ESM JS package, no types
import { suggestLines, think } from "../../../packages/brain/index.js";

type Store = {
  pets: Record<string, PetRecord>; // keyed by name
  nullifiers: string[];
  pending: Record<string, Pending>; // campaign id -> pet key -> count
  lines: Record<string, string>; // lineHash -> ad line text (the chain only stores the hash)
  brands: Record<string, string>; // brand address -> display name
  today: Record<string, { day: string; count: number }>; // pet key -> impressions accepted today (UTC)
  thoughts: Record<string, Thought[]>; // pet key -> last 0G decisions with request IDs
  lastImpression: Record<string, number>; // "campaignId:petKey" -> ms of the last counted impression
};

// shortcut: one JSON file, single process; move to DATABASE_URL if the server ever runs twice
const STORE_FILE = new URL("../data.json", import.meta.url);
const store: Store = {
  pets: {}, nullifiers: [], pending: {}, lines: {}, brands: {}, today: {}, thoughts: {}, lastImpression: {},
  ...(existsSync(STORE_FILE) ? JSON.parse(readFileSync(STORE_FILE, "utf8")) : {}),
};
const utcDay = () => new Date().toISOString().slice(0, 10);
const save = () => writeFileSync(STORE_FILE, JSON.stringify(store, null, 2));

// Impressions are client-reported; this window plus one-human-one-pet is the defence. Mac app uses the same value.
const IMPRESSION_WINDOW_MS = 60_000;
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
});

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

/** Each entry is one sign-shown event. Only registered (World-verified) pets, at most one per campaign per window. */
function addImpressions(body: any) {
  if (!Array.isArray(body.impressions) || body.impressions.length === 0) throw bad("impressions must be a non-empty array");
  // validate all entries before touching the store so a bad batch changes nothing
  const rows = body.impressions.map((i: any) => {
    const pet = findPet(String(i?.petKey ?? ""));
    if (!pet) throw bad(`unknown pet ${i?.petKey}`);
    const id = String(i.campaignId);
    if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaignId must be a positive integer");
    return { id, petKey: pet.petKey };
  });
  let accepted = 0;
  for (const r of rows) {
    if (!countImpression(store.lastImpression, `${r.id}:${r.petKey}`, Date.now(), IMPRESSION_WINDOW_MS)) continue;
    accepted++;
    const p = (store.pending[r.id] ??= {});
    p[r.petKey] = (p[r.petKey] ?? 0) + 1;
    const t = store.today[r.petKey];
    store.today[r.petKey] = { day: utcDay(), count: (t?.day === utcDay() ? t.count : 0) + 1 };
  }
  save();
  return { accepted, pending: store.pending };
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
    // one tx per pet; txHash is the first so a one-pet demo gets a single link
    const count = settled.reduce((n, x) => n + x.count, 0);
    const amount = settled.reduce((n, x) => n + BigInt(x.amount), 0n).toString();
    return { txHash: settled[0]?.txHash ?? null, count, amount, campaignId: id, settled, pending: store.pending[id] ?? {}, error, seeded };
  } finally {
    settling.delete(id);
  }
}

/** The campaign the pet shows: the newest live one with a known line that can still pay for an impression, or null. */
async function activeCampaign() {
  const [created, block] = await Promise.all([
    pub.getContractEvents({ address: vault, abi, eventName: "CampaignCreated", fromBlock: deployBlock }),
    pub.getBlock(),
  ]);
  for (const ev of [...created].reverse()) { // newest first: a campaign funded mid-demo shows on the next poll
    const id = ev.args.id!;
    const [brand, budget, spent, rate, endTime, closed, lineHash] = await pub.readContract({
      address: vault, abi, functionName: "campaigns", args: [id],
    });
    if (closed || endTime <= block.timestamp || budget - spent < rate) continue;
    const view = campaignView({ id, brand, lineHash, rate }, store);
    if (view.line) return view; // a line the server never got can't go on the sign
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

const str = (v: unknown, max = 64) => (typeof v === "string" ? v.slice(0, max) : undefined);

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

/** 3 ad lines for a brand brief, one 0G call. No fallback lines: a failure is a 502 the web page shows. */
async function campaignLines(body: any) {
  const brief = str(body.brief, 500);
  if (!brief?.trim()) throw bad("brief is required");
  try {
    return { lines: await suggestLines(brief) };
  } catch (e: any) {
    throw new HttpError(502, e.message);
  }
}

/** Saves the line text for a campaign the brand just paid for, once it hashes to the onchain lineHash. */
async function saveCampaign(body: any) {
  const id = String(body.campaignId ?? "");
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaignId must be a positive integer");
  if (typeof body.txHash === "string" && /^0x[0-9a-fA-F]{64}$/.test(body.txHash)) {
    // the web app posts right after sending; wait for it so the campaign exists when we read it
    await pub.waitForTransactionReceipt({ hash: body.txHash, timeout: 60_000 });
  }
  const [brand, , , rate, , , onchainHash] = await pub.readContract({ address: vault, abi, functionName: "campaigns", args: [BigInt(id)] });
  if (rate === 0n) throw new HttpError(404, "unknown campaign");
  const h = checkLine(body.line, body.lineHash, onchainHash);
  store.lines[h] = body.line;
  const name = str(body.brand, 40);
  if (name) store.brands[brand] = name;
  save();
  return { ok: true };
}

async function route(req: IncomingMessage) {
  const { pathname, searchParams } = new URL(req.url ?? "/", "http://x");
  const m = req.method;
  if (m === "GET" && pathname === "/world/sign") return worldSign(searchParams.get("action"), RP_SIGNING_KEY!);
  if (m === "POST" && pathname === "/pets/register") return registerPet(await readBody(req));
  if (m === "POST" && pathname === "/impressions") return addImpressions(await readBody(req));
  if (m === "POST" && pathname.startsWith("/settle/")) return settle(pathname.slice(8));
  if (m === "GET" && pathname === "/campaigns/active") return activeCampaign();
  if (m === "POST" && pathname === "/campaigns/lines") return campaignLines(await readBody(req));
  if (m === "POST" && pathname === "/campaigns") return saveCampaign(await readBody(req));
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
// Loopback only: /think and /campaigns/lines spend real 0G and have no auth, so nothing on the venue wifi may reach them.
const host = process.env.HOST ?? "127.0.0.1";
createServer((req, res) => {
  if (cors(req, res)) return;
  route(req).then(
    (body) => reply(res, 200, body),
    (e) => {
      const status = e instanceof HttpError ? e.status : 502; // anything else is the chain or RPC failing
      if (status === 502) console.error(errMsg(e));
      reply(res, status, { error: errMsg(e) });
    },
  );
}).listen(port, host, () => console.log(`server on ${host}:${port}, vault ${vault}, chain ${chain.id}`));
