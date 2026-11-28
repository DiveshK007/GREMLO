// Pets: registration, device pairing, signed views, the pet as the Mac and web read it, AI thoughts and their
// billing, the diary, and the pet purse.

import { type IncomingMessage } from "node:http";
import { accountExists, accountInfo, balanceOf, explorer, isMissingAccount, operatorId, provider, seeded, send, txOutcome, vault, view, viewOn } from "../chain.ts";
import { overdue, owed, paymentMatches, purseAccount, purseFits, spendable, type PurseView } from "../purse.ts";
import { countImpression, level, markDay, streak, underDailyCap } from "../batch.ts";
import { petView, queuedViews, type Compute } from "../views.ts";
import { bad, HttpError, makeRegister, verifyWorldProof, type PetRecord } from "../register.ts";
import { capSet } from "../prune.ts";
import { addThought } from "../thoughts.ts";
import { worldSign } from "../web.ts";
import { checkOwnerSignature, deviceKey, keyId, mustBeFrom, pairMessage } from "../auth.ts";
import { createHash } from "node:crypto";
import { addMoment, anonPet } from "../trust.ts";
import { hold } from "../fraud.ts";
import { checkViewable } from "../viewable.ts";
import { sumSince, WEEK_MS } from "../mail.ts";
import { diary, think } from "../../../../packages/brain/index.js";
import { type Body, type Loose } from "../json.ts";
import {
  HOLDBACK_HOURS,
  NOT_HANDLED,
  type OnchainPet,
  REQUIRE_SIGNED,
  RP_ID,
  RP_SIGNING_KEY,
  type Url,
  appendLog,
  clientIp,
  errMsg,
  fees,
  findPet,
  parse,
  readBody,
  readRaw,
  reserve,
  save,
  saveNow,
  settleErrors,
  signer,
  store,
  str,
  utcDay,
} from "../state.ts";

// Impressions are client-reported; this window plus one-human-one-pet is the defence. Mac app uses the same value.
const IMPRESSION_WINDOW_MS = 60_000;
const PET_STORAGE_DEPOSIT = 10_000_000_000_000_000_000_000n; // 0.01 NEAR; the vault refunds what storage doesn't use

// Every hook event reads the pet; 30s keeps a tool burst from hammering the RPC. Only successes are cached.
const balanceCache = new Map<string, { at: number; yocto: bigint }>();
async function payoutBalance(payout: string) {
  const hit = balanceCache.get(payout);
  if (hit && Date.now() - hit.at < 30_000) return hit.yocto;
  try {
    const y = await balanceOf(payout);
    balanceCache.set(payout, { at: Date.now(), yocto: y });
    return y;
  } catch (e) {
    console.error(`balance of ${payout}: ${errMsg(e)}`);
    return null;
  }
}

const registerPet = makeRegister({
  verify: (result) => verifyWorldProof(result, RP_ID),
  // idempotent, so a retry after a failed set_verified finishes the job instead of hitting "already registered"
  registerOnChain: async (pet, owner, payout) => {
    const existing = await view<OnchainPet | null>("get_pet", { pet_id: pet });
    if (existing && existing.owner !== owner) throw new HttpError(409, "pet already registered");
    const registerTx = existing ? "" : await send("register_pet", { pet_id: pet, owner, payout }, PET_STORAGE_DEPOSIT);
    const verifyTx = existing?.verified ? "" : await send("set_verified", { pet_id: pet, verified: true });
    return { registerTx, verifyTx };
  },
  accountExists,
  store,
  save: saveNow,
});

const usedPairNonces = new Set<string>();
/**
 * Pair a device to a pet: the pet's owner signs the pairing message with their NEAR wallet (NEP-413), using a
 * full-access key of the owner account. recipient is the vault id; the 32-byte nonce is never accepted twice.
 */
async function pairDevice(name: string, body: Body) {
  const pet = findPet(name);
  if (!pet) throw new HttpError(404, "unknown pet");
  const key = String(body?.key ?? "");
  deviceKey(key); // 400 if not a P-256 public key
  await checkOwnerSignature(body, pet.owner, pairMessage(pet.name, keyId(key)), vault, provider, usedPairNonces);
  const devices = (pet.devices ??= []);
  if (!devices.includes(key)) {
    // at most 5: the owner just signed for this one, so the oldest pairing makes room (a reinstalled Mac gets a new key)
    if (devices.length >= 5) console.log(`pair: ${pet.name} replaced its oldest device ${keyId(devices.shift()!)}`);
    devices.push(key);
    saveNow();
  }
  return { ok: true, pet: pet.name, device: keyId(key) };
}

/** Each entry is one sign-shown event. Only registered (World-verified) pets, at most one per campaign per window. */
function addImpressions(req: IncomingMessage, raw: string) {
  const body = parse(raw);
  if (!Array.isArray(body.impressions) || body.impressions.length === 0) throw bad("impressions must be a non-empty array");
  const signed = signer(req, "/impressions", raw); // verified once per request, then checked per row
  const ipTag = createHash("sha256").update(clientIp(req)).digest("hex").slice(0, 12); // for the one-network rule; raw IP never stored
  // validate all entries before touching the store so a bad batch changes nothing
  const rows = body.impressions.map((i: Body) => {
    const pet = findPet(String(i?.petKey ?? ""));
    if (!pet) throw bad(`unknown pet ${i?.petKey}`);
    // a view is money: it counts only from a paired Mac, locally too, so every paid view is a signed report that
    // gremlo verify can check (think and clicks stay lenient locally for development)
    mustBeFrom(pet, signed, true);
    const id = String(i.campaignId);
    if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaignId must be a positive integer");
    const hook = i.hook === undefined ? null : Number(i.hook);
    if (hook !== null && !(Number.isInteger(hook) && hook >= 0 && hook < 5)) throw bad("hook must be 0-4");
    try {
      checkViewable(i);
    } catch (e) {
      console.log(`view: ${pet.name} campaign ${id} refused: ${errMsg(e)}`);
      throw e;
    }
    return { id, petKey: pet.petKey, hook, moment: String(i.moment ?? "any") };
  });
  let accepted = 0;
  const logged: Record<string, number[]> = {}; // campaign -> accepted per line, for the public log
  for (const r of rows) {
    const t0 = store.today[r.petKey];
    if (!underDailyCap(t0?.day === utcDay() ? t0.count : 0)) {
      console.log(`view: ${r.petKey} campaign ${r.id} skipped: daily cap reached`);
      continue;
    } // respect the developer: 120 views a day at most
    if (!countImpression(store.lastImpression, `${r.id}:${r.petKey}`, Date.now(), IMPRESSION_WINDOW_MS)) {
      console.log(`view: ${r.petKey} campaign ${r.id} skipped: one per minute`);
      continue;
    }
    accepted++;
    console.log(`view: ${r.petKey} campaign ${r.id} hook ${r.hook ?? "-"} counted; held ${HOLDBACK_HOURS}h, then the worker settles it`);
    hold((store.held[r.id] ??= []), r.petKey, Math.floor(Date.now() / 3_600_000), ipTag); // paid after holdback + rules
    if (r.hook !== null) (store.hookViews[r.id] ??= [0, 0, 0, 0, 0])[r.hook]++;
    addMoment((store.momentViews[r.id] ??= {}), r.moment, r.petKey);
    // per campaign and pet; slot 4 holds sightings that named no line, so per-line totals stay exact
    (logged[`${r.id}|${r.petKey}`] ??= [0, 0, 0, 0, 0])[r.hook ?? 4]++;
    const t = store.today[r.petKey];
    store.today[r.petKey] = { day: utcDay(), count: (t?.day === utcDay() ? t.count : 0) + 1 };
    store.days[r.petKey] = markDay(store.days[r.petKey], utcDay());
  }
  // every counted sighting is backed by the pet's own signed report, chained in the campaign's public log
  const h = (k: string) => {
    const v = req.headers[k] ?? req.headers[k.replace("x-gremlo-", "x-notchi-")];
    return typeof v === "string" ? v : null;
  };
  for (const [k, counts] of Object.entries(logged)) {
    const [id, petKey] = k.split("|");
    appendLog(id, {
      campaign: id,
      hour: Math.floor(Date.now() / 3_600_000),
      counts,
      pet: anonPet(petKey),
      key: signed ? h("x-gremlo-key") : null,
      time: signed ? h("x-gremlo-time") : null,
      sig: signed ? h("x-gremlo-sig") : null,
      body: raw,
    });
  }
  saveNow(); // the log file and its head in the store must agree after a crash
  return { accepted, pending: store.pending };
}

/** A registered pet as the Mac and web read it: mood from its onchain compute budget, earnings from the vault. */
async function getPet(key: string, device: string | null = null) {
  const rec = findPet(key);
  if (!rec) throw new HttpError(404, "unknown pet");
  const petKey = rec.petKey;
  let pet: OnchainPet | null = null;
  try {
    pet = await view<OnchainPet | null>("get_pet", { pet_id: petKey });
    if (!pet) throw new HttpError(404, "pet not registered onchain");
  } catch (e) {
    if (e instanceof HttpError) throw e;
    console.error(`get_pet ${petKey}: ${errMsg(e)}`); // RPC down: the pet still answers, asleep, and says why
  }
  // shortcut: "today" uses this server's UTC clock, which can disagree with the chain's for a few seconds at midnight
  const today = Math.floor(Date.now() / 86_400_000);
  const vaultCompute: Compute | null = pet && {
    budget: BigInt(pet.compute_budget),
    chargedToday: pet.charge_day === today ? BigInt(pet.charged_today) : 0n,
    dailyCap: BigInt(pet.daily_cap),
  };
  // a pet with a purse thinks on its purse: mood from what the purse can still spend, minus what it already owes
  const pp = await purseOf(rec, pet?.owner ?? rec.owner);
  const compute: Compute | null = pp ? { budget: pp.spendable, chargedToday: BigInt(pp.view.spent_today), dailyCap: BigInt(pp.view.daily) } : vaultCompute;
  const t = store.today[petKey];
  return {
    ...petView({
      name: rec.name,
      walletBalance: pet ? await payoutBalance(pet.payout) : null, // the payout account, where earnings land
      compute,
      fees,
      inflight: (pp ? owed(store.thoughts[petKey]) : 0n) + reserve.held(petKey),
      impressionsToday: t?.day === utcDay() ? t.count : 0,
      seeded,
      lastThoughts: store.thoughts[petKey],
    }),
    petKey,
    species: rec.species ? rec.species.replace(/^gremlo-/, "") : null, // as the Mac last reported it; null until then
    paired: !!rec.devices?.length, // whether a Mac is paired (views count only from one); never the keys themselves
    // whether the asking Mac's own key is paired: a reinstall makes a new key, so `paired` alone can say yes while every view gets a 401
    thisDevicePaired: device ? !!rec.devices?.includes(device) : null,
    views: {
      ...queuedViews(store.held, store.pending, petKey),
      holdbackHours: HOLDBACK_HOURS,
      settledToday: store.payouts.filter((x) => x.pet === petKey && x.at >= Date.parse(utcDay())).reduce((n, x) => n + x.views, 0),
      settleError: settleErrors.get(petKey) ?? null,
    },
    stage: rec.stage ?? null,
    // settlement txs that fed this pet's compute budget: each is one meal (a receipt) for growth on the Mac
    meals: store.payouts
      .filter((x) => x.pet === petKey && x.tx)
      .map((x) => x.tx!)
      .slice(-500),
    owner: pet?.owner ?? rec.owner,
    payout: pet?.payout ?? rec.payout,
    purse: pp ? { account: pp.account, perCall: pp.view.per_call, daily: pp.view.daily } : null,
    compute: pp
      ? {
          budget: pp.spendable.toString(),
          spent: pp.view.total_paid,
          chargedToday: pp.view.spent_today,
          dailyCap: pp.view.daily,
          shareBps: pet?.compute_share_bps ?? 0,
          feeSmart: fees.smart.toString(),
          feeCheap: fees.cheap.toString(),
        }
      : pet && {
          budget: pet.compute_budget,
          spent: pet.compute_spent,
          chargedToday: vaultCompute!.chargedToday.toString(),
          dailyCap: pet.daily_cap,
          shareBps: pet.compute_share_bps,
          feeSmart: fees.smart.toString(),
          feeCheap: fees.cheap.toString(),
        },
    paidViews: pet ? pet.views : null,
    earnedWei: pet ? pet.earned : null, // yoctoNEAR paid to the payout account (name kept for the Mac and web)
    level: pet ? level(pet.views) : null,
    streak: streak(store.days[petKey], utcDay()),
    week: (({ views, wei }) => ({ views, wei: wei.toString() }))(sumSince(store.payouts, Date.now() - WEEK_MS, (p) => p.pet === petKey)),
    explorer,
    vault,
  };
}

/**
 * One pet decision from a Claude Code hook. The pet pays for it: the onchain compute budget picks the model
 * (enough for the smart rate: smart; for the cheap rate: cheap; less: no AI call, the pet sleeps hungry), and every
 * served completion is charged with charge_compute and its completion id. A sleep is a valid answer, so it is 200 too.
 */
const LOOK_SPECIES = ["gremlo", "gremlo-pip", "gremlo-moss", "gremlo-gloop", "gremlo-byte", "gremlo-puff", "gremlo-wisp", "gremlo-tako"];
const LOOK_STAGES = ["egg", "hatchling", "buddy", "elder"];
/** The Mac says which species it is and how grown, so the pet page can draw it. Cosmetic only: never money or mood. */
function rememberLook(key: string, body: Body) {
  const rec = findPet(key);
  const sp = String(body?.species),
    st = String(body?.stage);
  const species = LOOK_SPECIES.includes(sp) ? sp : undefined,
    stage = LOOK_STAGES.includes(st) ? st : undefined;
  if (!rec || (!species && !stage) || (rec.species === (species ?? rec.species) && rec.stage === (stage ?? rec.stage))) return;
  if (species) rec.species = species;
  if (stage) rec.stage = stage;
  save();
}

/** What the chain says this pet can still spend today, in yoctoNEAR, minus what a purse already owes. */
function room(pet: { compute: { budget: string; chargedToday: string; dailyCap: string } | null; petKey: string }, purse: boolean) {
  const c = pet.compute;
  if (!c) return 0n;
  const left = [BigInt(c.budget), BigInt(c.dailyCap) - BigInt(c.chargedToday)].reduce((a, b) => (a < b ? a : b));
  return left - (purse ? owed(store.thoughts[pet.petKey]) : 0n);
}
const COMMITTED = "sleeping: its compute budget is committed to another thought";

async function petThink(key: string, body: Body) {
  const event = str(body.event);
  if (!event) throw bad("event is required");
  const pet = await getPet(key); // 404s for unknown pets; mood comes from the same place as GET /pets/:name
  const petKey = pet.petKey;
  rememberLook(key, body);
  const fee = pet.mood === "thriving" ? fees.smart : fees.cheap;
  const blocked = purseGate(pet, fee);
  if (blocked) return { action: "sleep", say: null, reason: blocked, requestId: null, fee: null };
  // hold the fee before the slow AI call, so a second thought sent meanwhile sees it as spent
  const paid = pet.mood === "thriving" || pet.mood === "stable";
  if (paid && !reserve.tryHold(petKey, room(pet, !!pet.purse), fee)) return { action: "sleep", say: null, reason: COMMITTED, requestId: null, fee: null };
  let keep = false; // true while charge() owns the hold
  try {
    const r = await think({ event, mood: pet.mood, toolName: str(body.toolName), notificationType: str(body.notificationType) });
    if (!r.requestId && pet.moodReason) r.reason = pet.moodReason; // no call was made; say why in the pet's words
    store.thoughts[petKey] = addThought(store.thoughts[petKey], r);
    store.days[petKey] = markDay(store.days[petKey], utcDay());
    save();
    const served = r.completionId ? fee : 0n;
    const payFor = r.completionId ? bill(petKey, pet.purse, fee, r.completionId, r.action) : null;
    keep = !!served && !pet.purse;
    return { ...r, fee: served ? served.toString() : null, payFor };
  } finally {
    if (paid && !keep) reserve.release(petKey, fee); // no completion, a purse thought (now owed), or a failure
  }
}

/** The opt-in diary entry (1.0 design §8): counts and tool names only, one cheap call, charged like a think. */
const diaryDays = new Map<string, string>(); // pet -> UTC day of its last entry: one a day
async function petDiary(key: string, body: Body) {
  const pet = await getPet(key);
  const n = (v: unknown) => (Number.isInteger(v) && (v as number) >= 0 && (v as number) < 100_000 ? (v as number) : 0);
  const tools = Object.fromEntries(
    Object.entries(body?.tools ?? {})
      .filter(([k]) => /^[A-Za-z0-9_.:-]{1,64}$/.test(k))
      .slice(0, 20)
      .map(([k, v]) => [k, n(v)]),
  );
  const today = utcDay();
  if (diaryDays.get(pet.petKey) === today) throw new HttpError(429, "one diary entry a day");
  const blocked = purseGate(pet, fees.cheap);
  if (blocked) return { entry: null, reason: blocked, requestId: null };
  const paid = pet.mood === "thriving" || pet.mood === "stable"; // a hungry or asleep pet makes no call
  if (paid && !reserve.tryHold(pet.petKey, room(pet, !!pet.purse), fees.cheap)) return { entry: null, reason: COMMITTED, requestId: null };
  let keep = false;
  try {
    const r = await diary({
      mood: pet.mood,
      species: str(body?.species, 24),
      voice: str(body?.voice, 60),
      runs: n(body?.runs),
      failures: n(body?.failures),
      approvals: n(body?.approvals),
      tools,
      length: body?.length === "longer" ? "longer" : "short",
    });
    if (!r.entry) {
      // a completion that came back unusable was still served; the hold stays until it is charged
      if (r.completionId) {
        bill(pet.petKey, pet.purse, fees.cheap, r.completionId, "diary");
        keep = !pet.purse;
      }
      return { entry: null, reason: pet.moodReason ?? r.reason, requestId: r.requestId ?? null };
    }
    diaryDays.set(pet.petKey, today);
    const payFor = r.completionId ? bill(pet.petKey, pet.purse, fees.cheap, r.completionId, "diary") : null;
    keep = !!r.completionId && !pet.purse;
    return { entry: r.entry, requestId: r.requestId, fee: fees.cheap.toString(), payFor };
  } finally {
    if (paid && !keep) reserve.release(pet.petKey, fees.cheap);
  }
}

// ---------- the pet's purse (purse.ts) ----------
const PURSE_PARENT = process.env.PURSE_PARENT ?? ""; // where the purse factory runs (contracts-accounts); empty: no purses
type PetPurse = { account: string; view: PurseView; spendable: bigint };
const purseCache = new Map<string, { at: number; v: PetPurse | null }>();
/** The pet's purse when it fits (owned by the pet's owner, allowed to pay this operator); null otherwise. Cached 30 s. */
async function purseOf(rec: PetRecord, owner: string): Promise<PetPurse | null> {
  if (!PURSE_PARENT) return null;
  const hit = purseCache.get(rec.name);
  if (hit && Date.now() - hit.at < 30_000) return hit.v;
  const account = purseAccount(rec.name, PURSE_PARENT);
  let v: PetPurse | null = null;
  try {
    const pv = await viewOn<PurseView>(account, "get_purse");
    if (purseFits(pv, owner, operatorId)) {
      const a = await accountInfo(account);
      v = { account, view: pv, spendable: spendable(a.amount, a.storageUsage) };
    }
  } catch (e) {
    // no account or no purse code means this pet has no purse; anything else is the RPC, and the vault stays in charge
    if (!isMissingAccount(e) && !/CodeDoesNotExist|MethodNotFound|MethodResolveError/i.test(errMsg(e))) console.error(`purse ${account}: ${errMsg(e)}`);
  }
  purseCache.set(rec.name, { at: Date.now(), v });
  return v;
}
/** The deterministic budget check for purse pets: no paid thought while one is overdue or the fee is over the cap. */
function purseGate(pet: { petKey: string; purse: { perCall: string } | null }, fee: bigint) {
  if (!pet.purse) return null;
  if (overdue(store.thoughts[pet.petKey])) return "sleeping: the last thought isn't paid for yet";
  if (fee > BigInt(pet.purse.perCall)) return "sleeping: the purse's per-call cap is below the fee";
  return null;
}
/** Bills one served completion: a purse pet owes it (the Mac pays, /paid checks it); any other pet is charged in the vault. */
function bill(petKey: string, purse: { account: string } | null, fee: bigint, completionId: string, action: string) {
  if (!purse) {
    void charge(petKey, fee, completionId);
    return null;
  }
  let t = store.thoughts[petKey]?.find((x) => x.requestId === completionId);
  if (!t) {
    store.thoughts[petKey] = addThought(store.thoughts[petKey], { action, requestId: completionId });
    t = store.thoughts[petKey][0];
  }
  t.due = fee.toString();
  t.payTo = operatorId;
  saveNow();
  return { requestId: completionId, amount: t.due, payTo: operatorId, purse: purse.account };
}
/** The Mac reports a purse payment; it counts only once the chain shows the purse paid exactly this thought. */
async function pursePaid(name: string, b: Body) {
  const rec = findPet(name);
  if (!rec) throw new HttpError(404, "unknown pet");
  const requestId = str(b?.requestId, 128),
    tx = str(b?.tx, 64);
  if (!requestId || !tx || !/^[1-9A-HJ-NP-Za-km-z]{32,64}$/.test(tx)) throw bad("requestId and a base58 tx hash are required");
  const t = store.thoughts[rec.petKey]?.find((x) => x.requestId === requestId);
  if (!t?.due || !t.payTo) throw new HttpError(404, "no payment is owed for that thought");
  if (t.chargeTx) return { ok: true, tx: t.chargeTx };
  if (!PURSE_PARENT) throw new HttpError(409, "this server has no purse factory set");
  const account = purseAccount(rec.name, PURSE_PARENT);
  const out = await txOutcome(tx, account);
  if (!out) throw new HttpError(409, "that transaction isn't final yet; try again in a few seconds");
  if (!paymentMatches(out, { purse: account, provider: t.payTo, amount: t.due, requestId })) throw new HttpError(400, "that transaction isn't this purse paying for this thought");
  t.chargeTx = tx;
  purseCache.delete(rec.name); // the balance moved
  saveNow();
  console.log(`purse: ${rec.name} paid ${t.due} yoctoNEAR for ${requestId}, tx ${tx}`);
  return { ok: true, tx };
}

/** charge_compute for one served completion; the tx hash lands on the thought. A failure is logged, never invented. */
async function charge(petKey: string, fee: bigint, completionId: string) {
  try {
    // the fee was held before the AI call (petThink); it comes off once the charge lands or fails
    const tx = await send("charge_compute", { pet_id: petKey, amount: fee.toString(), near_ai_completion_id: completionId });
    const t = store.thoughts[petKey]?.find((x) => x.requestId === completionId);
    if (t) t.chargeTx = tx;
    saveNow();
    console.log(`charge: ${petKey} paid ${fee} yoctoNEAR for completion ${completionId}, tx ${tx}`);
  } catch (e) {
    console.error(`charge: ${petKey} completion ${completionId} was not charged: ${errMsg(e)}`);
  } finally {
    reserve.release(petKey, fee);
  }
}

/** The pet routes, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname, searchParams }: Url): Promise<Loose> {
  const m = req.method;
  if (m === "GET" && pathname === "/world/sign") return worldSign(searchParams.get("action"), RP_SIGNING_KEY);
  if (m === "POST" && pathname === "/pets/register") return registerPet(await readBody(req));
  if (m === "POST" && pathname === "/impressions") return addImpressions(req, await readRaw(req));
  const pair = pathname.match(/^\/pets\/([^/]+)\/device$/);
  if (m === "POST" && pair) return pairDevice(decodeURIComponent(pair[1]), await readBody(req));
  const paidPath = pathname.match(/^\/pets\/([^/]+)\/paid$/);
  if (m === "POST" && paidPath) return pursePaid(decodeURIComponent(paidPath[1]), await readBody(req));
  const thinkPath = pathname.match(/^\/pets\/([^/]+)\/think$/);
  if (m === "POST" && thinkPath) {
    const raw = await readRaw(req);
    const pet = findPet(decodeURIComponent(thinkPath[1]));
    const signed = signer(req, pathname, raw); // think spends real NEAR AI credits
    if (pet) mustBeFrom(pet, signed, REQUIRE_SIGNED);
    return petThink(decodeURIComponent(thinkPath[1]), parse(raw));
  }
  const diaryPath = pathname.match(/^\/pets\/([^/]+)\/diary$/);
  if (m === "POST" && diaryPath) {
    const raw = await readRaw(req);
    const pet = findPet(decodeURIComponent(diaryPath[1]));
    const signed = signer(req, pathname, raw); // a paid call, like think
    if (pet) mustBeFrom(pet, signed, REQUIRE_SIGNED);
    return petDiary(decodeURIComponent(diaryPath[1]), parse(raw));
  }
  if (m === "GET" && pathname.startsWith("/pets/")) return getPet(decodeURIComponent(pathname.slice(6)), searchParams.get("device"));
  return NOT_HANDLED;
}

export function housekeeping() {
  for (const [k, d] of diaryDays) if (d !== utcDay()) diaryDays.delete(k);
  capSet(usedPairNonces, 5_000);
}
