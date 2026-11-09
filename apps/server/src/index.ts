import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { BaseError, getAddress, isAddress, verifyMessage } from "viem";
import { abi, chain, deployBlock, pub, seeded, send, vault } from "./chain.ts";
import { allow, countImpression, hookOrder, level, markDay, markSettled, planSettlement, streak, underDailyCap, workFor, type Pending } from "./batch.ts";
import { campaignView, petView } from "./views.ts";
import { bad, HttpError, makeRegister, verifyWorldProof, type PetRecord } from "./register.ts";
import { addThought, type Thought } from "./thoughts.ts";
import { checkLine, checkUrl, clickTarget, cors, WEB_ORIGIN, worldSign } from "./web.ts";
import { canonical, checkSigned, deviceKey, keyId, mustBeFrom, pairMessage } from "./auth.ts";
import { arkivCampaign, publishCampaign, publishReceipt } from "./arkiv.ts";
import { alertDue, bestHook, checkEmail, mailOn, sendMail, sumSince, usedPct, WEEK_MS, weeklyReport, type Payout } from "./mail.ts";
// @ts-expect-error plain ESM JS package, no types
import { suggestHooks, think } from "../../../packages/brain/index.js";
// @ts-expect-error plain ESM JS package, no types
import { checkBrief, checkHook } from "../../../packages/brain/claims.js";

type Store = {
  pets: Record<string, PetRecord>; // keyed by name
  nullifiers: string[];
  pending: Record<string, Pending>; // campaign id -> pet key -> count
  lines: Record<string, string>; // lineHash -> ad line text (the chain only stores the hash)
  brands: Record<string, string>; // brand address -> display name
  today: Record<string, { day: string; count: number }>; // pet key -> impressions accepted today (UTC)
  thoughts: Record<string, Thought[]>; // pet key -> last 0G decisions with request IDs
  lastImpression: Record<string, number>; // "campaignId:petKey" -> ms of the last counted impression
  urls: Record<string, string>; // campaign id -> brand landing page (https)
  briefs: Record<string, Brief>; // campaign id -> the brand's brief (private, never served)
  hookViews: Record<string, number[]>; // campaign id -> counted impressions per hook index
  clicks: Record<string, number[]>; // campaign id -> deduped sign clicks per hook index
  lastClick: Record<string, number>; // "campaignId:petKey" -> ms of the last counted click
  days: Record<string, string[]>; // pet key -> recent UTC days with a hook event or a counted view (streaks)
  payouts: Payout[]; // settlements this server sent, newest last (weekly numbers); the chain stays the record
  emails: Record<string, string>; // campaign id -> brand email for alerts (private, never served)
  alerted: Record<string, number>; // campaign id -> last budget alert level emailed
  reported: Record<string, number>; // campaign id -> ms of the last weekly report
};
type Brief = { product: string; audience: string; offer: string; proof: string; cta: string };

// shortcut: one JSON file, one process; fine for a single instance on a persistent volume (STORE_PATH).
// Move to Postgres (PLAN_V2 A2) before running a second instance.
const STORE_FILE = process.env.STORE_PATH ?? new URL("../data.json", import.meta.url).pathname;
const store: Store = {
  pets: {}, nullifiers: [], pending: {}, lines: {}, brands: {}, today: {}, thoughts: {}, lastImpression: {},
  urls: {}, briefs: {}, hookViews: {}, clicks: {}, lastClick: {}, days: {}, payouts: [], emails: {}, alerted: {}, reported: {},
  ...(existsSync(STORE_FILE) ? JSON.parse(readFileSync(STORE_FILE, "utf8")) : {}),
};
const utcDay = () => new Date().toISOString().slice(0, 10);
// write-then-rename, so a crash mid-write can never leave a truncated store
const save = () => {
  writeFileSync(`${STORE_FILE}.tmp`, JSON.stringify(store, null, 2));
  renameSync(`${STORE_FILE}.tmp`, STORE_FILE);
};

// Impressions are client-reported; this window plus one-human-one-pet is the defence. Mac app uses the same value.
const IMPRESSION_WINDOW_MS = 60_000;
const REQUIRE_SIGNED = process.env.REQUIRE_SIGNED === "1"; // production: views, think and clicks must be device-signed
/** The visitor's IP; behind a host proxy (TRUST_PROXY=1) it comes from the proxy's header, not the socket. */
const clientIp = (req: IncomingMessage) => {
  if (process.env.TRUST_PROXY === "1") {
    const h = req.headers["fly-client-ip"] ?? req.headers["x-real-ip"] ?? String(req.headers["x-forwarded-for"] ?? "").split(",")[0];
    if (typeof h === "string" && h.trim()) return h.trim();
  }
  return req.socket.remoteAddress ?? "unknown";
};
const CLICK_WINDOW_MS = 10 * 60_000; // one counted click per pet per campaign per 10 minutes
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

async function readRaw(req: IncomingMessage) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 100_000) throw new HttpError(413, "body too large");
  }
  return raw;
}
const parse = (raw: string) => { try { return raw ? JSON.parse(raw) : {}; } catch { throw bad("invalid JSON"); } };
async function readBody(req: IncomingMessage) {
  return parse(await readRaw(req));
}

// ---- device signatures (PLAN_V2 A3) ----
const seenSigs = new Map<string, number>();
const petByDevice = (key: string) => Object.values(store.pets).find((p) => p.devices?.includes(key));

/**
 * The pet a request is signed by, or null when unsigned. A pet with a paired device must sign: an unsigned
 * request for it is a 401, and a signed one must come from one of its own devices.
 */
function signer(req: IncomingMessage, path: string, raw: string) {
  const key = req.headers["x-notchi-key"], time = req.headers["x-notchi-time"], sig = req.headers["x-notchi-sig"];
  if (typeof key !== "string" || typeof time !== "string" || typeof sig !== "string") return null;
  checkSigned({ key, time, sig, message: canonical(req.method ?? "GET", path, time, raw), now: Date.now(), seen: seenSigs });
  const pet = petByDevice(key);
  if (!pet) throw new HttpError(401, "device is not paired to any pet");
  return pet;
}


/** Pair a device to a pet: the pet's owner signs the pairing message with their wallet. */
async function pairDevice(name: string, body: any) {
  const pet = findPet(name);
  if (!pet) throw new HttpError(404, "unknown pet");
  const key = String(body?.key ?? "");
  deviceKey(key); // 400 if not a P-256 public key
  const signature = String(body?.signature ?? "");
  if (!/^0x[0-9a-fA-F]+$/.test(signature)) throw bad("signature is required");
  const ok = await verifyMessage({ address: getAddress(pet.owner), message: pairMessage(pet.name, keyId(key)), signature: signature as `0x${string}` }).catch(() => false);
  if (!ok) throw new HttpError(403, "signature is not from this pet's owner");
  const devices = (pet.devices ??= []);
  if (!devices.includes(key)) {
    if (devices.length >= 5) throw bad("a pet can have at most 5 paired devices; unpair one first");
    devices.push(key);
    save();
  }
  return { ok: true, pet: pet.name, device: keyId(key) };
}

/** Each entry is one sign-shown event. Only registered (World-verified) pets, at most one per campaign per window. */
function addImpressions(req: IncomingMessage, raw: string) {
  const body = parse(raw);
  if (!Array.isArray(body.impressions) || body.impressions.length === 0) throw bad("impressions must be a non-empty array");
  const signed = signer(req, "/impressions", raw); // verified once per request, then checked per row
  // validate all entries before touching the store so a bad batch changes nothing
  const rows = body.impressions.map((i: any) => {
    const pet = findPet(String(i?.petKey ?? ""));
    if (!pet) throw bad(`unknown pet ${i?.petKey}`);
    mustBeFrom(pet, signed, REQUIRE_SIGNED);
    const id = String(i.campaignId);
    if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaignId must be a positive integer");
    const hook = i.hook === undefined ? null : Number(i.hook);
    if (hook !== null && !(Number.isInteger(hook) && hook >= 0 && hook < 5)) throw bad("hook must be 0-4");
    return { id, petKey: pet.petKey, hook };
  });
  let accepted = 0;
  for (const r of rows) {
    const t0 = store.today[r.petKey];
    if (!underDailyCap(t0?.day === utcDay() ? t0.count : 0)) continue; // respect the developer: 120 views a day at most
    if (!countImpression(store.lastImpression, `${r.id}:${r.petKey}`, Date.now(), IMPRESSION_WINDOW_MS)) continue;
    accepted++;
    const p = (store.pending[r.id] ??= {});
    p[r.petKey] = (p[r.petKey] ?? 0) + 1;
    if (r.hook !== null) (store.hookViews[r.id] ??= [0, 0, 0, 0, 0])[r.hook]++;
    const t = store.today[r.petKey];
    store.today[r.petKey] = { day: utcDay(), count: (t?.day === utcDay() ? t.count : 0) + 1 };
    store.days[r.petKey] = markDay(store.days[r.petKey], utcDay());
  }
  save();
  return { accepted, pending: store.pending };
}

async function settle(id: string) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  if (settling.has(id)) throw new HttpError(409, "settlement already running for this campaign");
  settling.add(id);
  try {
    const [, , , rate, endTime, closed] = await pub.readContract({ address: vault, abi, functionName: "campaigns", args: [BigInt(id)] });
    if (rate === 0n) throw new HttpError(404, "unknown campaign");
    if (closed) throw new HttpError(409, `campaign #${id} is closed; nothing more can be paid from it`);
    // the contract pays only until 1 hour after the end; say so instead of sending a tx that reverts
    const { timestamp } = await pub.getBlock();
    if (timestamp > endTime + 3600n) {
      const queued = Object.values(store.pending[id] ?? {}).reduce((a, b) => a + b, 0);
      throw new HttpError(409, `campaign #${id}'s settlement window closed at ${new Date(Number(endTime + 3600n) * 1000).toLocaleTimeString()}; ${queued} queued impression${queued === 1 ? "" : "s"} can't be paid. Close it to refund the rest.`);
    }
    const remaining = await pub.readContract({ address: vault, abi, functionName: "remaining", args: [BigInt(id)] });
    const plan = planSettlement(store.pending[id] ?? {}, rate, remaining);

    const settled = [];
    let error: string | undefined;
    for (const s of plan.settle) {
      try {
        const txHash = await send("settleImpressions", [BigInt(id), s.pet, BigInt(s.count)]);
        // deduct only what was paid, one pet at a time, so a failure mid-batch loses nothing
        markSettled(store.pending[id], s.pet, s.count, "paid");
        store.payouts = [...store.payouts, { at: Date.now(), id, pet: getAddress(s.pet), views: s.count, wei: s.amount.toString() }].slice(-5000);
        save();
        settled.push({ petKey: s.pet, count: s.count, amount: s.amount.toString(), txHash });
        void publishReceipt({ campaignId: id, pet: getAddress(s.pet), views: s.count, amountWei: s.amount, settleTx: txHash, chainId: chain.id, endTime });
      } catch (e: any) {
        markSettled(store.pending[id], s.pet, s.count, e?.unconfirmedTx ? "unconfirmed" : "failed");
        save();
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
    // a line the server never got can't go on the sign; `order` is the auto-optimised rotation for the next slots
    if (view.line) return { ...view, order: hookOrder(store.hookViews[view.campaignId] ?? [], store.clicks[view.campaignId] ?? [], view.hooks.length) };
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
  // earnings straight from the chain's settlements; null (not 0) when the chain can't be read
  const earned = await settledEvents().then(
    (ev) => ev.filter((e) => e.args.pet && getAddress(e.args.pet) === petKey)
      .reduce((a, e) => ({ views: a.views + Number(e.args.count ?? 0n), wei: a.wei + (e.args.amount ?? 0n) }), { views: 0, wei: 0n }),
    () => null,
  );
  return {
    ...petView({
    name: rec?.name ?? petKey.toLowerCase(),
    walletBalance: await payoutBalance(getAddress(payout!)), // payout is where the pet's earnings land
    thresholds,
    impressionsToday: t?.day === utcDay() ? t.count : 0,
    seeded,
    lastThoughts: store.thoughts[petKey],
    }),
    paidViews: earned?.views ?? null,
    earnedWei: earned?.wei.toString() ?? null,
    level: earned ? level(earned.views) : null,
    streak: streak(store.days[petKey], utcDay()),
    week: (({ views, wei }) => ({ views, wei: wei.toString() }))(sumSince(store.payouts, Date.now() - WEEK_MS, (p) => p.pet === petKey)),
  };
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
  store.days[petKey] = markDay(store.days[petKey], utcDay());
  save();
  return r;
}

/** A brand brief from the web form. Field limits are the trust boundary; the claim checks run on top. */
function parseBrief(b: any): Brief {
  const field = (k: string, max: number, required: boolean) => {
    const v = typeof b?.[k] === "string" ? b[k].trim() : "";
    if (required && !v) throw bad(`${k} is required`);
    if (v.length > max) throw bad(`${k} must be at most ${max} characters`);
    return v;
  };
  return { product: field("product", 160, true), audience: field("audience", 120, true), offer: field("offer", 120, false), proof: field("proof", 600, false), cta: field("cta", 40, true) };
}

/** Brief + chosen hooks pass every claim check, or a 400 that names the hook and the reason. No 0G call. */
function checkCampaign(rawBrief: unknown, hooks: string[]) {
  const brief = parseBrief(rawBrief);
  const refused = checkBrief(brief);
  if (refused) throw bad(refused);
  if (hooks.length < 1 || hooks.length > 5) throw bad("pick 1 to 5 hooks");
  for (const hook of hooks) {
    const why = checkHook(hook, brief);
    if (why) throw bad(`"${hook}": ${why}`);
  }
  return brief;
}

/** 2 hooks per format from one 0G call; hooks that fail the claim checks come back in `dropped` with the reason. */
const hooksHits = new Map<string, number[]>();
async function campaignHooks(req: IncomingMessage, body: any) {
  if (body?.attest !== true) throw bad("confirm the proof points are your own, accurate claims");
  // each call is a large 0G request: 10 per visitor per hour
  if (!allow(hooksHits, clientIp(req), Date.now(), 10, 3_600_000)) throw new HttpError(429, "That's 10 hook sets this hour. Pick from the ones you have, or try again later.");
  const brief = parseBrief(body?.brief);
  checkUrl(body?.url);
  try {
    return await suggestHooks(brief);
  } catch (e: any) {
    if (e.code === "brief") throw bad(e.message);
    throw Object.assign(new HttpError(502, e.message), { requestId: e.requestId });
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
  const [brand, , , rate, endTime, , onchainHash] = await pub.readContract({ address: vault, abi, functionName: "campaigns", args: [BigInt(id)] });
  if (rate === 0n) throw new HttpError(404, "unknown campaign");
  const line = Array.isArray(body.hooks) ? body.hooks.map((x: unknown) => String(x)).join("\n") : body.line;
  // the browser is not trusted to have run the checks: every hook, picked or hand-written, runs them again here
  if (body.brief !== undefined) store.briefs[id] = checkCampaign(body.brief, String(line).split("\n"));
  const h = checkLine(line, body.lineHash, onchainHash);
  store.lines[h] = line;
  if (body.url !== undefined) store.urls[id] = checkUrl(body.url);
  const email = checkEmail(body.email);
  if (email) store.emails[id] = email;
  // public, self-expiring card on Arkiv; never blocks the brand (failures are logged)
  void publishCampaign({ id, brand, hooks: line.split("\n"), url: store.urls[id] ?? "", rateWei: rate, endTime, chainId: chain.id, fundingTx: String(body.txHash ?? "") });
  const name = str(body.brand, 40);
  if (name) store.brands[brand] = name;
  save();
  return { ok: true };
}

/** A sign click: counted at most once per pet per campaign per window, then off to the brand with UTM tags. */
function signClick(id: string, hookStr: string, petKey: string | null, q: URLSearchParams) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  const url = store.urls[id];
  if (!url) throw new HttpError(404, "this campaign has no link");
  const hook = Number(hookStr);
  if (!(Number.isInteger(hook) && hook >= 0 && hook < 5)) throw bad("hook must be 0-4");
  // a browser can't send headers, so a click carries its device signature in the query (over the pet name)
  let pet = petKey ? findPet(petKey) : undefined;
  if (pet) {
    const key = q.get("key"), time = q.get("t"), sig = q.get("sig");
    if (key && time && sig) {
      // a bad signature never blocks the developer's click: it just isn't counted
      try {
        checkSigned({ key, time, sig, message: canonical("GET", `/c/${id}/${hookStr}`, time, petKey!), now: Date.now(), seen: seenSigs });
        if (petByDevice(key)?.petKey !== pet.petKey) pet = undefined;
      } catch {
        pet = undefined;
      }
    } else if (pet.devices?.length || REQUIRE_SIGNED) pet = undefined; // unsigned click: still redirect, never count
  }
  if (pet && countImpression(store.lastClick, `${id}:${pet.petKey}`, Date.now(), CLICK_WINDOW_MS)) {
    (store.clicks[id] ??= [0, 0, 0, 0, 0])[hook]++;
    save();
  }
  return { redirect: clickTarget(url, id, hook) };
}

/** What a brand sees for one campaign: per-hook views and clicks, queued views, link. Brief stays private. */
function campaignStats(id: string) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  const views = store.hookViews[id] ?? [0, 0, 0, 0, 0], clicks = store.clicks[id] ?? [0, 0, 0, 0, 0];
  const pending = Object.values(store.pending[id] ?? {}).reduce((a, b) => a + b, 0);
  return { campaignId: id, url: store.urls[id] ?? null, views, clicks, pendingViews: pending, best: bestHook(views, clicks), emailAlerts: mailOn && !!store.emails[id] };
}

/** Homepage numbers, read from the chain's own events (never seeded). Cached for a minute. */
let settledCache: { at: number; events: Promise<{ args: { pet?: `0x${string}`; count?: bigint; amount?: bigint } }[]> } | null = null;
/** Every ImpressionsSettled event, read from the chain at most once a minute (shared by /stats and pet earnings). */
function settledEvents() {
  if (!settledCache || Date.now() - settledCache.at > 60_000) {
    const events = pub.getContractEvents({ address: vault, abi, eventName: "ImpressionsSettled", fromBlock: deployBlock });
    settledCache = { at: Date.now(), events };
    events.catch(() => (settledCache = null)); // a failed read is retried on the next request
  }
  return settledCache.events;
}

let statsCache: { at: number; body: unknown } | null = null;
async function publicStats() {
  if (statsCache && Date.now() - statsCache.at < 60_000) return statsCache.body;
  const [created, settled] = await Promise.all([
    pub.getContractEvents({ address: vault, abi, eventName: "CampaignCreated", fromBlock: deployBlock }),
    settledEvents(),
  ]);
  const views = settled.reduce((a, e) => a + (e.args.count ?? 0n), 0n);
  const paid = settled.reduce((a, e) => a + (e.args.amount ?? 0n), 0n);
  const body = { campaigns: created.length, settledViews: views.toString(), paidWei: paid.toString(), pets: Object.keys(store.pets).length, chainId: chain.id, seeded };
  statsCache = { at: Date.now(), body };
  return body;
}

// "Try a hook" on the homepage: one real 0G call, limited per visitor and per day, cached by product.
const tryHits = new Map<string, number[]>();
const tryCache = new Map<string, { at: number; body: unknown }>();
const TRY_DAILY_CAP = Number(process.env.TRY_DAILY_CAP ?? 100);
let tryDay = { day: "", calls: 0 };
async function tryHook(req: IncomingMessage, body: any) {
  const product = str(body?.product, 160)?.trim();
  if (!product || product.length < 3) throw bad("say what your product is");
  const key = product.toLowerCase().replace(/\s+/g, " ");
  const hit = tryCache.get(key);
  if (hit && Date.now() - hit.at < 24 * 3_600_000) return hit.body;
  const ip = clientIp(req);
  if (!allow(tryHits, ip, Date.now(), 3, 3_600_000)) throw new HttpError(429, "That's 3 tries this hour. Fund a campaign to get all 16 hooks.");
  if (tryDay.day !== utcDay()) tryDay = { day: utcDay(), calls: 0 };
  if (tryDay.calls >= TRY_DAILY_CAP) throw new HttpError(429, "Today's free tries are used up. Come back tomorrow, or fund a campaign.");
  tryDay.calls++;
  try {
    const r = await suggestHooks({ product, audience: str(body?.audience, 120)?.trim() || "developers", offer: "", proof: "", cta: "Try it" });
    const seen = new Set<string>();
    const hooks = r.hooks.filter((h: { format: string }) => !seen.has(h.format) && seen.add(h.format)).slice(0, 3);
    const out = { hooks, requestId: r.requestId, example: true };
    tryCache.set(key, { at: Date.now(), body: out });
    return out;
  } catch (e: any) {
    if (e.code === "brief") throw bad(e.message);
    throw new HttpError(502, e.message);
  }
}

/**
 * Background worker: settles queued views while the contract still pays, and closes ended campaigns so the
 * unspent budget returns to the brand without anyone clicking. One pass at a time; errors are logged, not fatal.
 */
let working = false;
async function workerPass() {
  if (working) return;
  working = true;
  try {
    const [created, block] = await Promise.all([
      pub.getContractEvents({ address: vault, abi, eventName: "CampaignCreated", fromBlock: deployBlock }),
      pub.getBlock(),
    ]);
    for (const ev of created) {
      const id = ev.args.id!;
      try {
        const [, budget, spent, , endTime, closed, lineHash] = await pub.readContract({ address: vault, abi, functionName: "campaigns", args: [id] });
        const remaining = await pub.readContract({ address: vault, abi, functionName: "remaining", args: [id] });
        const pending = Object.values(store.pending[id.toString()] ?? {}).reduce((a, b) => a + b, 0);
        const job = workFor({ closed, endTime, remaining }, pending, block.timestamp);
        if (job === "settle") {
          const r = await settle(id.toString());
          console.log(`worker: settled campaign ${id}: ${r.count} views, txs ${r.settled.map((x) => x.txHash).join(", ") || "none"}${r.error ? `, stopped: ${r.error}` : ""}`);
        } else if (job === "refund") {
          console.log(`worker: closed campaign ${id}, refund tx ${await send("close", [id])}`);
        }
        if (!closed) await brandMail(id.toString(), budget, spent, lineHash);
      } catch (e) {
        console.error(`worker: campaign ${id}: ${errMsg(e)}`);
      }
    }
  } catch (e) {
    console.error(`worker: ${errMsg(e)}`);
  } finally {
    working = false;
  }
}
/** Budget alerts and the weekly report for one live campaign, when the brand left an email and mail is on. */
async function brandMail(id: string, budget: bigint, spent: bigint, lineHash: `0x${string}`) {
  const to = store.emails[id];
  if (!to || !mailOn) return;
  const link = `${WEB_ORIGIN}/brand?c=${id}`;
  const pct = usedPct(spent, budget), level = alertDue(pct, store.alerted[id] ?? 0);
  if (level && (await sendMail(to, `Notchi campaign #${id}: ${level}% of the budget is spent`,
    `${level >= 100 ? "Your budget is used up and your hooks have stopped showing." : `Campaign #${id} has spent ${pct}% of its budget.`}\nTop up or check the numbers: ${link}`))) {
    store.alerted[id] = level;
    save();
  }
  if (store.reported[id] === undefined) { store.reported[id] = Date.now(); return save(); } // first report a week after we first see it
  if (Date.now() - store.reported[id] < WEEK_MS) return;
  const humans = new Set([...store.payouts.filter((p) => p.id === id).map((p) => p.pet), ...Object.keys(store.pending[id] ?? {})]).size;
  const hooks = store.lines[lineHash]?.split("\n") ?? [];
  const text = weeklyReport({ id, hooks, views: store.hookViews[id] ?? [], clicks: store.clicks[id] ?? [], spent, budget, humans, link });
  if (await sendMail(to, `Notchi campaign #${id}: your week`, text)) {
    store.reported[id] = Date.now();
    save();
  }
}
if (process.env.WORKER !== "off") setInterval(workerPass, Number(process.env.WORKER_MINUTES ?? 10) * 60_000);

async function route(req: IncomingMessage) {
  const { pathname, searchParams } = new URL(req.url ?? "/", "http://x");
  const m = req.method;
  if (m === "GET" && pathname === "/health") return { ok: true }; // for the host's health check; touches nothing
  if (m === "GET" && pathname === "/world/sign") return worldSign(searchParams.get("action"), RP_SIGNING_KEY!);
  if (m === "POST" && pathname === "/pets/register") return registerPet(await readBody(req));
  if (m === "POST" && pathname === "/impressions") return addImpressions(req, await readRaw(req));
  const pair = pathname.match(/^\/pets\/([^/]+)\/device$/);
  if (m === "POST" && pair) return pairDevice(decodeURIComponent(pair[1]), await readBody(req));
  if (m === "POST" && pathname.startsWith("/settle/")) return settle(pathname.slice(8));
  if (m === "GET" && pathname === "/campaigns/active") return activeCampaign();
  if (m === "POST" && pathname === "/campaigns/hooks") return campaignHooks(req, await readBody(req));
  if (m === "GET" && pathname === "/stats") return publicStats();
  if (m === "POST" && pathname === "/try") return tryHook(req, await readBody(req));
  if (m === "POST" && pathname === "/campaigns/check") {
    // run before the brand pays, so nothing they wrote can be refused after the money moved
    const b = await readBody(req);
    checkCampaign(b?.brief, Array.isArray(b?.hooks) ? b.hooks.map(String) : []);
    return { ok: true, url: checkUrl(b?.url) };
  }
  const click = pathname.match(/^\/c\/([^/]+)\/([^/]+)$/);
  if (m === "GET" && click) return signClick(click[1], click[2], searchParams.get("pet"), searchParams);
  const stats = pathname.match(/^\/campaigns\/([^/]+)\/stats$/);
  if (m === "GET" && stats) return campaignStats(stats[1]);
  const ark = pathname.match(/^\/campaigns\/([1-9][0-9]*)\/arkiv$/);
  if (m === "GET" && ark) return arkivCampaign(ark[1]);
  if (m === "POST" && pathname === "/campaigns") return saveCampaign(await readBody(req));
  const thinkPath = pathname.match(/^\/pets\/([^/]+)\/think$/);
  if (m === "POST" && thinkPath) {
    const raw = await readRaw(req);
    const pet = findPet(decodeURIComponent(thinkPath[1]));
    const signed = signer(req, pathname, raw); // think spends real 0G
    if (pet) mustBeFrom(pet, signed, REQUIRE_SIGNED);
    return petThink(decodeURIComponent(thinkPath[1]), parse(raw));
  }
  if (m === "GET" && pathname.startsWith("/pets/")) return getPet(decodeURIComponent(pathname.slice(6)));
  throw new HttpError(404, "not found");
}

const reply = (res: ServerResponse, status: number, body: unknown) => {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};

const port = Number(process.env.PORT ?? 8787);
// Loopback by default. Expose it (HOST=0.0.0.0) only with REQUIRE_SIGNED=1 and TRUST_PROXY=1 set, as in fly.toml.
const host = process.env.HOST ?? "127.0.0.1";
if (host !== "127.0.0.1" && !REQUIRE_SIGNED) throw new Error("refusing to listen publicly without REQUIRE_SIGNED=1: unpaired pets could spend 0G");
createServer((req, res) => {
  if (cors(req, res)) return;
  route(req).then(
    (body: any) => {
      if (body?.redirect) { res.writeHead(302, { Location: body.redirect }); res.end(); return; }
      reply(res, 200, body);
    },
    (e) => {
      const status = e instanceof HttpError ? e.status : 502; // anything else is the chain or RPC failing
      if (status === 502) console.error(errMsg(e));
      reply(res, status, { error: errMsg(e) });
    },
  );
}).listen(port, host, () => console.log(`server on ${host}:${port}, vault ${vault}, chain ${chain.id}`));
