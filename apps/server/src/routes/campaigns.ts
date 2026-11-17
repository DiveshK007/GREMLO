// Campaigns: what the pet shows, brand briefs and hooks, the public totals and log, sign clicks, reports and "try a hook".

import { type IncomingMessage, type ServerResponse } from "node:http";
import { network, seeded, vault, view } from "../chain.ts";
import { allow, countImpression, makeDailyCap, hookOrder } from "../batch.ts";
import { campaignView } from "../views.ts";
import { bad, HttpError } from "../register.ts";
import { checkCampaign, parseBrief, saveLine } from "../campaigns.ts";
import { pruneHits } from "../prune.ts";
import { streamLog } from "../logstream.ts";
import { checkUrl, clickTarget } from "../web.ts";
import { canonical, checkSigned, mustBeFrom } from "../auth.ts";
import { arkivCampaign } from "../arkiv.ts";
import { momentTags, momentView, pausedLines } from "../trust.ts";
import { bestHook, checkEmail, mailOn } from "../mail.ts";
import { suggestHooks } from "../../../../packages/brain/index.js";
import { coded, type Body, type Loose } from "../json.ts";
import {
  HOLDBACK_HOURS,
  NOT_HANDLED,
  type OnchainCampaign,
  REQUIRE_SIGNED,
  type Url,
  clientIp,
  findPet,
  logFile,
  nowS,
  parse,
  petByDevice,
  readBody,
  readRaw,
  save,
  saveNow,
  seenSigs,
  signer,
  store,
  str,
  utcDay,
} from "../state.ts";

const CLICK_WINDOW_MS = 10 * 60_000; // one counted click per pet per campaign per 10 minutes
/** The newest 100 campaigns from the vault, oldest first. */
export async function campaigns() {
  const count = await view<number>("campaign_count");
  // shortcut: only the newest 100 are read; page through get_campaigns once a deployment has more
  return view<[number, OnchainCampaign][]>("get_campaigns", { from: Math.max(1, count - 99), limit: 100 });
}

/** The A/B rotation, rebalanced hourly (R2 §15). */
const orders = new Map<string, number[]>();
function hourlyOrder(id: string, n: number) {
  const k = `${id}:${n}:${Math.floor(Date.now() / 3_600_000)}`;
  if (!orders.has(k)) {
    orders.clear();
    orders.set(k, hookOrder(store.hookViews[id] ?? [], store.clicks[id] ?? [], n));
  }
  return orders.get(k)!;
}

/** The campaign the pet shows: the newest live one with a known line that can still pay for an impression, or null. */
async function activeCampaign() {
  const now = nowS();
  for (const [id, c] of [...(await campaigns())].reverse()) {
    // newest first: a campaign funded mid-demo shows on the next poll
    const rate = BigInt(c.rate);
    if (c.closed || BigInt(c.end_time) <= now || BigInt(c.budget) - BigInt(c.spent) < rate) continue;
    const view = campaignView({ id: BigInt(id), brand: c.brand, lineHash: `0x${c.line_hash}`, rate }, store);
    // a line the server never got can't go on the sign; `order` is the auto-optimised rotation for the next slots
    if (view.line) {
      const paused = pausedLines(store.reports[view.campaignId], store.hookViews[view.campaignId]);
      return { ...view, order: hourlyOrder(view.campaignId, view.hooks.length).filter((i) => !paused.includes(i)), paused, moments: store.moments[view.campaignId] ?? momentTags([], view.hooks.length) };
    }
  }
  return null;
}

/** 2 hooks per format from one NEAR AI call; hooks that fail the claim checks come back in `dropped` with the reason. */
const hooksHits = new Map<string, number[]>();
async function campaignHooks(req: IncomingMessage, body: Body) {
  if (body?.attest !== true) throw bad("confirm the proof points are your own, accurate claims");
  // each call is a large NEAR AI request: 10 per visitor per hour
  if (!allow(hooksHits, clientIp(req), Date.now(), 10, 3_600_000)) throw new HttpError(429, "That's 10 hook sets this hour. Pick from the ones you have, or try again later.");
  const brief = parseBrief(body?.brief);
  checkUrl(body?.url);
  try {
    return await suggestHooks(brief);
  } catch (err) {
    const e = coded(err);
    if (e.code === "brief") throw bad(e.message);
    throw Object.assign(new HttpError(502, e.message), { requestId: e.requestId });
  }
}

/** Saves the line text for a campaign the brand just paid for, once it hashes to the onchain lineHash. */
async function saveCampaign(body: Body) {
  const id = String(body.campaignId ?? "");
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaignId must be a positive integer");
  // the web app posts right after its tx; give RPC nodes a few seconds to see the new campaign
  let c: OnchainCampaign | null = null;
  for (let i = 0; i < 5 && !c; i++) {
    c = await view<OnchainCampaign | null>("get_campaign", { id: Number(id) });
    if (!c) await new Promise((r) => setTimeout(r, 2000));
  }
  if (!c) throw new HttpError(404, "unknown campaign");
  saveLine(store, id, c, body); // every check first, then the writes
  saveNow(); // the line text is only on this server; a crash must not lose it
  return { ok: true };
}

/**
 * A sign click: counted at most once per pet per campaign per window, then off to the brand with UTM tags.
 * It has to be a GET: the pet opens the browser on this address and the browser can only follow a redirect.
 * It is idempotent per device signature: checkSigned refuses a signature it has seen, so repeating a click URL
 * (a reload, a prefetch, a replay) still redirects but counts nothing, and the 10-minute window caps real clicks.
 */
function signClick(id: string, hookStr: string, petKey: string | null, q: URLSearchParams) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  const url = store.urls[id];
  if (!url) throw new HttpError(404, "this campaign has no link");
  const hook = Number(hookStr);
  if (!(Number.isInteger(hook) && hook >= 0 && hook < 5)) throw bad("hook must be 0-4");
  // a browser can't send headers, so a click carries its device signature in the query (over the pet name)
  let pet = petKey ? findPet(petKey) : undefined;
  if (pet) {
    const key = q.get("key"),
      time = q.get("t"),
      sig = q.get("sig");
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

async function campaignStats(id: string) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  // the line text, so the dashboard can show each line and not just "#1"; null when the contract can't be read
  const onchain = await view<OnchainCampaign | null>("get_campaign", { id: Number(id) }).catch(() => null);
  const lines = onchain ? (store.lines[`0x${onchain.line_hash}`]?.split("\n") ?? null) : null;
  const views = store.hookViews[id] ?? [0, 0, 0, 0, 0],
    clicks = store.clicks[id] ?? [0, 0, 0, 0, 0];
  const pending = Object.values(store.pending[id] ?? {}).reduce((a, b) => a + b, 0);
  const heldViews = (store.held[id] ?? []).reduce((a, h) => a + h.n, 0);
  return {
    campaignId: id,
    url: store.urls[id] ?? null,
    views,
    clicks,
    pendingViews: pending,
    heldViews,
    holdbackHours: HOLDBACK_HOURS,
    voided: store.voided[id] ?? {},
    best: bestHook(views, clicks),
    emailAlerts: mailOn && !!store.emails[id],
    moments: momentView(store.momentViews[id]),
    reports: store.reports[id] ?? [],
    paused: pausedLines(store.reports[id], views),
    lines,
  };
}

let statsCache: { at: number; body: unknown } | null = null;
/** Homepage numbers, read from the vault's own totals (never seeded). Cached for a minute. */
async function publicStats() {
  if (statsCache && Date.now() - statsCache.at < 60_000) return statsCache.body;
  const [count, totals] = await Promise.all([view<number>("campaign_count"), view<{ paid_to_pets: string; compute_budgets: string; compute_charged: string }>("get_totals")]);
  const views = store.settledViews ?? 0; // settled by this server; no RPC per pet on every refresh
  // everything settled to pets: paid out, plus compute budgets, plus what compute already charged
  const paid = BigInt(totals.paid_to_pets) + BigInt(totals.compute_budgets) + BigInt(totals.compute_charged);
  const body = { campaigns: count, settledViews: String(views), paidWei: paid.toString(), computeChargedWei: totals.compute_charged, pets: Object.keys(store.pets).length, network, vault, seeded };
  statsCache = { at: Date.now(), body };
  return body;
}

// "Try a hook" on the homepage: one real NEAR AI call, limited per visitor and per day, cached by product.
const tryHits = new Map<string, number[]>();
const tryCache = new Map<string, { at: number; body: unknown }>();
const TRY_DAILY_CAP = Number(process.env.TRY_DAILY_CAP ?? 100);
const tryCap = makeDailyCap(TRY_DAILY_CAP);
async function tryHook(req: IncomingMessage, body: Body) {
  const product = str(body?.product, 160)?.trim();
  if (!product || product.length < 3) throw bad("say what your product is");
  const key = product.toLowerCase().replace(/\s+/g, " ");
  const hit = tryCache.get(key);
  if (hit && Date.now() - hit.at < 24 * 3_600_000) return hit.body;
  const ip = clientIp(req);
  if (!allow(tryHits, ip, Date.now(), 3, 3_600_000)) throw new HttpError(429, "That's 3 tries this hour. Fund a campaign to get all 16 hooks.");
  const today = utcDay();
  if (!tryCap.take(today)) throw new HttpError(429, "Today's free tries are used up. Come back tomorrow, or fund a campaign.");
  try {
    const r = await suggestHooks({ product, audience: str(body?.audience, 120)?.trim() || "developers", offer: "", proof: "", cta: "Try it" });
    const seen = new Set<string>();
    const hooks = r.hooks.filter((h: { format: string }) => !seen.has(h.format) && seen.add(h.format)).slice(0, 3);
    const out = { hooks, requestId: r.requestId, example: true };
    tryCache.set(key, { at: Date.now(), body: out });
    return out;
  } catch (err) {
    const e = coded(err);
    tryCap.refund(today); // a call that failed doesn't use up one of the day's free tries
    if (e.code === "brief") throw bad(e.message);
    throw new HttpError(502, e.message);
  }
}

/** A campaign's public log and what was billed from it; `gremlo verify <campaign>` checks one against the other. */
function logBilled(id: string) {
  const settled = store.payouts.filter((p) => p.id === id).reduce((a, p) => a + p.views, 0);
  const pending = Object.values(store.pending[id] ?? {}).reduce((a, b) => a + b, 0);
  const held = (store.held[id] ?? []).reduce((a, x) => a + x.n, 0);
  const voided = Object.values(store.voided[id] ?? {}).reduce((a, b) => a + b, 0);
  return { campaign: id, billed: { settled, pending, held, voided } };
}
/** GET /campaigns/:id/log[?after=i]: streamed from the file, never loaded whole; `after` returns only newer entries. */
const publicLog = (id: string, after: number) => ({
  pipe: (res: ServerResponse) => streamLog(res, logFile(id), logBilled(id), Number.isInteger(after) && after > 0 ? after : 0),
});

/** "Report" from the menu bar: a signed pet only, once per pet per line per day. Enough reports pause the line. */
const reported = new Set<string>();
function reportLine(req: IncomingMessage, raw: string) {
  const b = parse(raw),
    signed = signer(req, "/lines/report", raw);
  const pet = findPet(String(b?.petKey ?? ""));
  if (!pet) throw bad("unknown pet");
  mustBeFrom(pet, signed, REQUIRE_SIGNED);
  const id = String(b?.campaignId ?? ""),
    hook = Number(b?.hook);
  if (!/^[1-9][0-9]*$/.test(id) || !(Number.isInteger(hook) && hook >= 0 && hook < 4)) throw bad("campaignId and hook 0-3");
  const k = `${utcDay()}:${pet.petKey}:${id}:${hook}`;
  if (reported.has(k)) return { ok: true };
  reported.add(k);
  (store.reports[id] ??= [0, 0, 0, 0])[hook]++;
  save();
  console.log(`report: campaign ${id} line ${hook} (${store.reports[id][hook]} reports)`);
  return { ok: true, paused: pausedLines(store.reports[id], store.hookViews[id]).includes(hook) };
}

/** The campaign routes, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname, searchParams }: Url): Promise<Loose> {
  const m = req.method;
  if (m === "GET" && pathname === "/campaigns/active") return activeCampaign();
  if (m === "POST" && pathname === "/campaigns/hooks") return campaignHooks(req, await readBody(req));
  if (m === "GET" && pathname === "/stats") return publicStats();
  if (m === "POST" && pathname === "/try") return tryHook(req, await readBody(req));
  if (m === "POST" && pathname === "/campaigns/check") {
    // run before the brand pays, so nothing they wrote can be refused after the money moved
    const b = await readBody(req);
    checkCampaign(b?.brief, Array.isArray(b?.hooks) ? b.hooks.map(String) : []);
    return { ok: true, url: checkUrl(b?.url), email: checkEmail(b?.email) ?? null };
  }
  const click = pathname.match(/^\/c\/([^/]+)\/([^/]+)$/);
  if (m === "GET" && click) return signClick(click[1], click[2], searchParams.get("pet"), searchParams);
  const stats = pathname.match(/^\/campaigns\/([^/]+)\/stats$/);
  if (m === "GET" && stats) return campaignStats(stats[1]);
  const ark = pathname.match(/^\/campaigns\/([1-9][0-9]*)\/arkiv$/);
  if (m === "GET" && ark) return arkivCampaign(ark[1]);
  if (m === "POST" && pathname === "/campaigns") return saveCampaign(await readBody(req));
  const log = pathname.match(/^\/campaigns\/([1-9][0-9]*)\/log$/);
  if (m === "GET" && log) return publicLog(log[1], Number(searchParams.get("after") ?? 0));
  if (m === "POST" && pathname === "/lines/report") return reportLine(req, await readRaw(req));
  return NOT_HANDLED;
}

export function housekeeping(now: number) {
  const DAY = 86_400_000;
  pruneHits(hooksHits, now, DAY);
  pruneHits(tryHits, now, DAY);
  for (const [k, v] of tryCache) if (now - v.at > DAY) tryCache.delete(k);
  for (const k of reported) if (!k.startsWith(utcDay())) reported.delete(k);
}
