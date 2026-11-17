import { bad, HttpError } from "./register.ts";
import { checkEmail } from "./mail.ts";
import { momentTags } from "./trust.ts";
import { checkLine, checkUrl } from "./web.ts";
// @ts-expect-error plain ESM JS package, no types
import { checkBrief, checkHook } from "../../../packages/brain/claims.js";

export type Brief = { product: string; audience: string; offer: string; proof: string; cta: string };
/** The slices of the store a campaign save touches. */
export type LineStore = {
  moments: Record<string, string[]>;
  urls: Record<string, string>;
  briefs: Record<string, Brief>;
  lines: Record<string, string>;
  emails: Record<string, string>;
  brands: Record<string, string>;
};

const str = (v: unknown, max = 64) => (typeof v === "string" ? v.slice(0, max) : undefined);

/** A brand brief from the web form. Field limits are the trust boundary; the claim checks run on top. */
export function parseBrief(b: any): Brief {
  const field = (k: string, max: number, required: boolean) => {
    const v = typeof b?.[k] === "string" ? b[k].trim() : "";
    if (required && !v) throw bad(`${k} is required`);
    if (v.length > max) throw bad(`${k} must be at most ${max} characters`);
    return v;
  };
  return { product: field("product", 160, true), audience: field("audience", 120, true), offer: field("offer", 120, false), proof: field("proof", 600, false), cta: field("cta", 40, true) };
}

/** Brief + chosen hooks pass every claim check, or a 400 that names the hook and the reason. No AI call. */
export function checkCampaign(rawBrief: unknown, hooks: string[]) {
  const brief = parseBrief(rawBrief);
  const refused = checkBrief(brief);
  if (refused) throw bad(refused);
  if (hooks.length < 1 || hooks.length > 4) throw bad("pick 1 to 4 lines");
  for (const hook of hooks) {
    const why = checkHook(hook, brief);
    if (why) throw bad(`"${hook}": ${why}`);
  }
  return brief;
}

/**
 * Saves the line text and details for a campaign the brand just paid for, once the line hashes to the onchain
 * lineHash. Every check runs before the first write, so a refused request leaves the store untouched: nobody
 * can lock a campaign out by sending a bad hash first.
 */
export function saveLine(store: LineStore, id: string, c: { brand: string; line_hash: string }, body: any) {
  const line = Array.isArray(body.hooks) ? body.hooks.map((x: unknown) => String(x)).join("\n") : body.line;
  // first write wins: the line text is private until this save, so only the brand can make a matching hash; after
  // that, nobody (who could now read the line) may swap the link, email or brief. A repeat of the same save is fine.
  if (store.moments[id] !== undefined || store.urls[id] !== undefined || store.briefs[id] !== undefined) {
    const same = (body.url === undefined || store.urls[id] === checkUrl(body.url)) && (body.email === undefined || store.emails[id] === body.email);
    if (!same) throw new HttpError(409, "this campaign's details are already saved");
    return { ok: true };
  }
  const hooks = String(line).split("\n");
  // the browser is not trusted to have run the checks: every hook, picked or hand-written, runs them again here
  const brief = body.brief !== undefined ? checkCampaign(body.brief, hooks) : undefined;
  if (hooks.length > 4) throw bad("at most 4 lines");
  const hash = checkLine(line, body.lineHash, `0x${c.line_hash}`);
  const url = body.url !== undefined ? checkUrl(body.url) : undefined;
  // checked before payment (/campaigns/check); after the money moved a bad address is dropped, never an error
  const email = (() => { try { return checkEmail(body.email); } catch { return undefined; } })();
  const name = str(body.brand, 40);

  store.lines[hash] = line;
  store.moments[id] = momentTags(body.moments, hooks.length);
  if (brief) store.briefs[id] = brief;
  if (url) store.urls[id] = url;
  if (email) store.emails[id] = email;
  if (name) store.brands[c.brand] = name;
  return { ok: true };
}
