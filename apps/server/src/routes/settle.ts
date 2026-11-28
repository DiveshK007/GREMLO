// Settlement: paying signed views from a campaign to pets, and the background worker that settles and closes campaigns.

import { type IncomingMessage } from "node:http";
import { accountExists, seeded, send, view } from "../chain.ts";
import { allow, cooldown, markSettled, planSettlement, workFor } from "../batch.ts";
import { bad, HttpError } from "../register.ts";
import { pruneHits, pruneStamps } from "../prune.ts";
import { WEB_ORIGIN } from "../web.ts";
import { review } from "../fraud.ts";
import { alertDue, mailOn, sendMail, usedPct, WEEK_MS, weeklyReport } from "../mail.ts";
import { PRODUCT } from "../../../../packages/brain/product.js";
import { coded, type Loose } from "../json.ts";
import { campaigns } from "./campaigns.ts";
import { HOLDBACK_HOURS, NOT_HANDLED, type OnchainCampaign, type OnchainPet, type Url, clientIp, errMsg, nowS, save, saveNow, settleErrors, store } from "../state.ts";

const settling = new Set<string>(); // campaigns with a settlement in flight

const settleHits = new Map<string, number[]>();
const settleAt = new Map<string, number>();
/** POST /settle/:id from a browser: a cooldown per campaign and a limit per visitor, so it can't be used to burn gas. */
async function settleRequest(req: IncomingMessage, id: string) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  if (!allow(settleHits, clientIp(req), Date.now(), 20, 3_600_000)) throw new HttpError(429, "Too many settlement requests from this address. Try again in an hour.");
  const wait = cooldown(settleAt, id, Date.now(), 60_000);
  if (wait) throw new HttpError(429, `Campaign #${id} was just settled. Try again in ${Math.ceil(wait / 1000)} seconds.`);
  return settle(id);
}
async function settle(id: string) {
  if (!/^[1-9][0-9]*$/.test(id)) throw bad("campaign id must be a positive integer");
  if (settling.has(id)) throw new HttpError(409, "settlement already running for this campaign");
  settling.add(id);
  try {
    const c = await view<OnchainCampaign | null>("get_campaign", { id: Number(id) });
    if (!c) throw new HttpError(404, "unknown campaign");
    if (c.closed) throw new HttpError(409, `campaign #${id} is closed; nothing more can be paid from it`);
    const rate = BigInt(c.rate),
      endTime = BigInt(c.end_time),
      timestamp = nowS();
    // the contract pays only until 1 hour after the end; say so instead of sending a tx that fails
    if (timestamp > endTime + 3600n) {
      const queued = Object.values(store.pending[id] ?? {}).reduce((a, b) => a + b, 0) + (store.held[id] ?? []).reduce((a, h) => a + h.n, 0);
      throw new HttpError(
        409,
        `campaign #${id}'s settlement window closed at ${new Date(Number(endTime + 3600n) * 1000).toLocaleTimeString()}; ${queued} queued impression${queued === 1 ? "" : "s"} can't be paid. Close it to refund the rest.`,
      );
    }
    release(id, timestamp >= endTime);
    const remaining = BigInt(await view<string>("remaining", { id: Number(id) }));
    const plan = planSettlement(store.pending[id] ?? {}, rate, remaining);

    const settled = [];
    let error: string | undefined;
    for (const s of plan.settle) {
      try {
        // a transfer to a missing account fails and strands the NEAR in the vault, so check the payout first
        const pet = await view<OnchainPet | null>("get_pet", { pet_id: s.pet });
        if (pet && !(await accountExists(pet.payout))) {
          throw new Error(`pet ${s.pet}'s payout account ${pet.payout} does not exist; its owner must set one that does (set_payout)`);
        }
        // the vault refuses unverified pets; saying so here saves a failing tx's gas every worker pass
        if (pet && !pet.verified) throw new Error(`pet ${s.pet} isn't verified onchain; register it again on the web to finish verification`);
        const txHash = await send("settle_impressions", { id: Number(id), pet_id: s.pet, count: s.count });
        // deduct only what was paid, one pet at a time, so a failure mid-batch loses nothing
        markSettled(store.pending[id], s.pet, s.count, "paid");
        store.settledViews = (store.settledViews ?? 0) + s.count;
        store.payouts = [...store.payouts, { at: Date.now(), id, pet: s.pet, views: s.count, wei: s.amount.toString(), tx: txHash }].slice(-5000);
        saveNow();
        settled.push({ petKey: s.pet, count: s.count, amount: s.amount.toString(), txHash });
        settleErrors.delete(s.pet);
        console.log(`settle: campaign ${id} paid ${s.pet} for ${s.count} views (${s.amount} yoctoNEAR), tx ${txHash}`);
      } catch (err) {
        const e = coded(err);
        markSettled(store.pending[id], s.pet, s.count, e.unconfirmedTx ? "unconfirmed" : "failed");
        if (e.unconfirmedTx) console.error(`settle: campaign ${id} ${s.pet} unconfirmed, tx ${e.unconfirmedTx}; held back, not resent (check it on the explorer)`);
        saveNow();
        error ??= errMsg(e);
        settleErrors.set(s.pet, errMsg(e));
        // an unconfirmed tx means the RPC is in doubt: stop. Any other failure is this pet's; the pets after it still get paid.
        if (e.unconfirmedTx) break;
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

/** Moves views that waited out the holdback into the payable queue, voiding what the fraud rules flag. */
function release(id: string, ended: boolean) {
  const held = store.held[id];
  if (!held?.length) return;
  // once the campaign has ended the contract pays for one more hour only, so nothing may wait past that
  const r = review(held, Math.floor(Date.now() / 3_600_000), ended ? 0 : HOLDBACK_HOURS);
  const p = (store.pending[id] ??= {});
  for (const h of r.ok) p[h.pet] = (p[h.pet] ?? 0) + h.n;
  const v = (store.voided[id] ??= {});
  for (const h of r.voided) v[h.reason] = (v[h.reason] ?? 0) + h.n;
  if (r.ok.length) console.log(`release: campaign ${id}: ${r.ok.reduce((a, h) => a + h.n, 0)} views now payable`);
  if (r.voided.length) console.log(`fraud: campaign ${id} voided ${r.voided.reduce((a, h) => a + h.n, 0)} views`);
  store.held[id] = r.waiting;
  saveNow();
}

/**
 * Background worker: settles queued views while the contract still pays, and closes ended campaigns so the
 * unspent budget returns to the brand without anyone clicking. One pass at a time; errors are logged, not fatal.
 */
let working = false;
export const WORKER_ON = process.env.WORKER !== "off",
  WORKER_MS = Number(process.env.WORKER_MINUTES ?? 10) * 60_000;
export const worker = { startedAt: Date.now(), lastOk: null as number | null, lastError: null as string | null, expiredUnpaid: 0 };
async function workerPass() {
  if (working) return;
  working = true;
  let failed = false;
  try {
    const now = nowS();
    for (const [id, c] of await campaigns()) {
      try {
        const endTime = BigInt(c.end_time),
          remaining = c.closed ? 0n : BigInt(c.budget) - BigInt(c.spent);
        release(String(id), now >= endTime);
        const pending = Object.values(store.pending[String(id)] ?? {}).reduce((a, b) => a + b, 0);
        const job = workFor({ closed: c.closed, endTime, remaining }, pending, now);
        const held = (store.held[String(id)] ?? []).reduce((a, h) => a + h.n, 0);
        if (!c.closed && (job !== "none" || pending || held)) console.log(`worker: campaign ${id}: ${pending} payable, ${held} held, job ${job}`);
        if (job === "refund" && pending) {
          worker.expiredUnpaid += pending;
          console.error(`worker: campaign ${id}: ${pending} views expired unpaid (the vault pays only until 1h after the end)`);
        }
        if (job === "settle") {
          const r = await settle(String(id));
          console.log(`worker: settled campaign ${id}: ${r.count} views, txs ${r.settled.map((x) => x.txHash).join(", ") || "none"}${r.error ? `, failed: ${r.error}` : ""}`);
        } else if (job === "refund") {
          console.log(`worker: closed campaign ${id}, refund tx ${await send("close", { id })}`);
        }
        if (!c.closed) await brandMail(String(id), BigInt(c.budget), BigInt(c.spent), `0x${c.line_hash}`);
      } catch (e) {
        failed = true;
        worker.lastError = `campaign ${id}: ${errMsg(e)}`;
        console.error(`worker: campaign ${id}: ${errMsg(e)}`);
      }
    }
  } catch (e) {
    failed = true;
    worker.lastError = errMsg(e);
    console.error(`worker: ${errMsg(e)}`);
  } finally {
    if (!failed) worker.lastOk = Date.now();
    working = false;
  }
}
/** Budget alerts and the weekly report for one live campaign, when the brand left an email and mail is on. */
async function brandMail(id: string, budget: bigint, spent: bigint, lineHash: string) {
  const to = store.emails[id];
  if (!to || !mailOn) return;
  const link = `${WEB_ORIGIN}/brand?c=${id}`;
  const pct = usedPct(spent, budget),
    level = alertDue(pct, store.alerted[id] ?? 0);
  if (
    level &&
    (await sendMail(
      to,
      `${PRODUCT} campaign #${id}: ${level}% of the budget is spent`,
      `${level >= 100 ? "Your budget is used up and your hooks have stopped showing." : `Campaign #${id} has spent ${pct}% of its budget.`}\nTop up or check the numbers: ${link}`,
    ))
  ) {
    store.alerted[id] = level;
    save();
  }
  if (store.reported[id] === undefined) {
    store.reported[id] = Date.now();
    return save();
  } // first report a week after we first see it
  if (Date.now() - store.reported[id] < WEEK_MS) return;
  const humans = new Set([...store.payouts.filter((p) => p.id === id).map((p) => p.pet), ...Object.keys(store.pending[id] ?? {})]).size;
  const hooks = store.lines[lineHash]?.split("\n") ?? [];
  const text = weeklyReport({ id, hooks, views: store.hookViews[id] ?? [], clicks: store.clicks[id] ?? [], spent, budget, humans, link });
  if (await sendMail(to, `${PRODUCT} campaign #${id}: your week`, text)) {
    store.reported[id] = Date.now();
    save();
  }
}
if (WORKER_ON) setInterval(workerPass, WORKER_MS);

/** The settlement route, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname }: Url): Promise<Loose> {
  if (req.method === "POST" && pathname.startsWith("/settle/")) return settleRequest(req, pathname.slice(8));
  return NOT_HANDLED;
}

export function housekeeping(now: number) {
  pruneHits(settleHits, now, 86_400_000);
  pruneStamps(settleAt, now, 60_000);
}
