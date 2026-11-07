// Pet decisions and ad lines via the 0G Compute Router (OpenAI-compatible). Never invents output:
// think() safe-stops to {action: "sleep", reason}; suggestHooks() throws with the real error.

export const ACTIONS = ['wake', 'work', 'wave', 'wait', 'celebrate', 'sad', 'go_home', 'sleep'];

const SYSTEM = `You are Notchi, a small desktop pet that watches a coding agent.
Given the pet state as JSON, pick one action from: ${ACTIONS.join(', ')}.
Reply with only a JSON object: {"action": "<one action>", "say": "<at most 8 words>"}.`;

import { FORMATS, MAX_HOOK, checkBrief, checkHook } from './claims.js';

const FORMAT_GUIDE = {
  humour: 'a light joke a developer would smile at, then the product',
  sarcasm: 'dry, self-aware sarcasm about the problem the product solves; never mean about people',
  offer: 'the offer itself, made hard to ignore; use the offer words exactly',
  question: 'a question the reader answers yes to, then the product',
  'bold-claim': 'one confident claim taken word for word from the proof points',
  urgency: 'a reason to act now, only if the offer gives one; never invent deadlines or scarcity',
  story: 'a one-sentence story: the problem, then the product',
  'dev-meme': 'a developer in-joke (prod on Friday, merge conflicts, "works on my machine") tied to the product',
};

const HOOKS_SYSTEM = `You write sponsored hooks that a small desktop pet carries across a developer's screen while their coding agent works.
For EACH format below write exactly 2 different hooks, each at most ${MAX_HOOK} characters, plain English, specific to the product.
${FORMATS.map((f) => `- ${f}: ${FORMAT_GUIDE[f]}`).join('\n')}
Hard rules:
- Use only numbers, results, comparisons and claims that appear in the brief's PROOF POINTS or OFFER, copied exactly. Never invent statistics, customers, speeds, prices, deadlines or rankings.
- No superlatives (best, fastest, only, #1) unless they are in the proof points.
- Never promise money, returns, profit or gains.
- No emoji, no links, no hashtags. Use the call to action when it fits.
Reply with only a JSON object: {"hooks": [{"format": "<format>", "text": "<hook>"}, ...]}.`;

const SMART = process.env.ZG_MODEL_SMART || process.env.ZG_MODEL;
const CHEAP = process.env.ZG_MODEL_CHEAP || process.env.ZG_MODEL;
if (!SMART || !CHEAP) {
  throw new Error('brain: set ZG_MODEL_SMART and ZG_MODEL_CHEAP (or ZG_MODEL as fallback for both) in .env');
}
export const MODEL_BY_MOOD = { thriving: SMART, stable: CHEAP, hungry: CHEAP };

/**
 * One router call. Returns {out, content, requestId, cost}: out is the parsed JSON object from the reply,
 * or null when it has none (content is the raw text). Throws Error with .requestId on transport/HTTP failure.
 */
async function chat(system, user, model, opts) {
  const base = opts.base ?? process.env.ZG_API_BASE ?? 'https://router-api.0g.ai/v1';
  const key = opts.key ?? process.env.ZG_API_KEY ?? '';
  const doFetch = opts.fetch ?? fetch;
  let requestId = null;
  const fail = (msg) => Object.assign(new Error(msg), { requestId });
  let res;
  try {
    res = await doFetch(`${base}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
        max_tokens: opts.maxTokens ?? 2048, // reasoning models spend tokens before content; a Stop decision used 982 of 1024
      }),
      signal: AbortSignal.timeout(opts.timeoutMs ?? 20000),
    });
  } catch (err) {
    throw fail(`0G unreachable: ${err.message}`);
  }
  const text = await res.text();
  let data = null;
  try { data = JSON.parse(text); } catch {}
  requestId = data?.x_0g_trace?.request_id ?? res.headers.get('x-request-id') ?? null;
  if (!res.ok) throw fail(`0G HTTP ${res.status}: ${text.slice(0, 300)}`);
  const content = data?.choices?.[0]?.message?.content ?? '';
  const match = content.match(/\{[\s\S]*\}/);
  let out = null;
  try { out = match && JSON.parse(match[0]); } catch {}
  return { out, content, requestId, cost: data.x_0g_trace?.billing?.total_cost ?? null };
}

export async function think(state, opts = {}) {
  if (state?.mood === 'asleep') return sleep('asleep: no paid calls', null);
  const model = MODEL_BY_MOOD[state?.mood];
  if (!model) return sleep(`unknown mood: ${state?.mood}`, null);
  try {
    const { out, content, requestId, cost } = await chat(SYSTEM, JSON.stringify(state), model, opts);
    if (!out) return sleep(`0G reply had no JSON: ${content.slice(0, 200)}`, requestId);
    if (!ACTIONS.includes(out.action)) return sleep(`0G picked unknown action: ${out.action}`, requestId);
    return { action: out.action, say: String(out.say ?? '').slice(0, 80), requestId, cost };
  } catch (err) {
    return sleep(err.message, err.requestId);
  }
}

const HOOKS_STRICT = `${HOOKS_SYSTEM}\nReply with JSON only: no prose, no code fences, nothing before or after the object.`;

/**
 * Hooks for a brand brief: 2 per format from one 0G call (retried once if the reply has no JSON).
 * Every hook passes checkHook or is returned in `dropped` with the reason. Nothing is made up here:
 * no hooks that pass means a throw carrying the real request ID.
 */
export async function suggestHooks(brief, opts = {}) {
  opts = { timeoutMs: 120000, maxTokens: 8192, ...opts }; // 16 hooks after the reasoning model thinks
  const refused = checkBrief(brief);
  if (refused) throw Object.assign(new Error(refused), { code: 'brief' });
  const user = JSON.stringify({ product: brief.product, audience: brief.audience, offer: brief.offer ?? '', proofPoints: brief.proof ?? '', callToAction: brief.cta });
  let r = await chat(HOOKS_SYSTEM, user, SMART, opts);
  if (!Array.isArray(r.out?.hooks)) r = await chat(HOOKS_STRICT, user, SMART, opts);
  const raw = Array.isArray(r.out?.hooks) ? r.out.hooks : [];
  const hooks = [], dropped = [], perFormat = {};
  for (const h of raw) {
    const format = String(h?.format ?? '').toLowerCase(), text = String(h?.text ?? '').trim();
    if (!FORMATS.includes(format)) continue;
    const reason = checkHook(text, brief);
    if (reason) { dropped.push({ format, text, reason }); continue; }
    if ((perFormat[format] = (perFormat[format] ?? 0) + 1) > 2) continue;
    hooks.push({ format, text, requestId: r.requestId });
  }
  if (!hooks.length || !r.requestId) {
    throw Object.assign(new Error(raw.length ? '0G wrote no hooks that pass the claim checks' : '0G reply had no hooks'), { requestId: r.requestId, dropped });
  }
  return { hooks, dropped, requestId: r.requestId };
}

function sleep(reason, requestId) {
  return { action: 'sleep', reason, requestId };
}
