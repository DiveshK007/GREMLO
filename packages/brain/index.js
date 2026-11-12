// Pet decisions and ad lines via NEAR AI Cloud (OpenAI-compatible, TEE inference). Never invents output:
// think() safe-stops to {action: "sleep", reason}; suggestHooks() throws with the real error.

export const ACTIONS = ['wake', 'work', 'wave', 'wait', 'celebrate', 'sad', 'go_home', 'sleep'];

const SYSTEM = `You are a small desktop pet that watches a coding agent.
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

// Defaults are NEAR-hosted models (owned_by "nearai" in /v1/models), served from attested TEEs.
const SMART = process.env.NEAR_AI_MODEL_SMART || 'deepseek-ai/DeepSeek-V4.1-Flash-1017';
const CHEAP = process.env.NEAR_AI_MODEL_CHEAP || 'Qwen/Qwen3.8-27B';
// hungry and asleep make no call: the pet can't pay for one (see the server's compute budget)
export const MODEL_BY_MOOD = { thriving: SMART, stable: CHEAP };

/**
 * One chat call. Returns {out, content, requestId, usage}: out is the parsed JSON object from the reply,
 * or null when it has none (content is the raw text). requestId is the completion `id`, which
 * GET /v1/signature/{id} and cloud.near.ai/verify accept. Throws Error with .requestId on transport/HTTP failure;
 * there it is the X-Request-Id header, since a failed call has no completion id.
 */
async function chat(system, user, model, opts) {
  const base = opts.base ?? (process.env.NEAR_AI_BASE_URL || 'https://cloud-api.near.ai/v1'); // an empty value in .env means the default
  const key = opts.key ?? process.env.NEAR_AI_API_KEY ?? '';
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
    const why = [err.message, err.cause?.code, err.cause?.message].filter(Boolean).join(': '); // "fetch failed" alone says nothing
    throw fail(`NEAR AI unreachable (${new URL(base).host}): ${why}`);
  }
  const text = await res.text();
  let data = null;
  try { data = JSON.parse(text); } catch {}
  requestId = res.headers.get('x-request-id');
  if (!res.ok) throw fail(`NEAR AI HTTP ${res.status}: ${text.slice(0, 300)}`);
  requestId = typeof data?.id === 'string' && data.id ? data.id : null;
  const content = data?.choices?.[0]?.message?.content ?? '';
  const match = content.match(/\{[\s\S]*\}/);
  let out = null;
  try { out = match && JSON.parse(match[0]); } catch {}
  return { out, content, requestId, completionId: requestId, usage: data?.usage ?? null };
}

export async function think(state, opts = {}) {
  if (state?.mood === 'asleep' || state?.mood === 'hungry') return sleep(`${state.mood}: no paid calls`, null);
  const model = MODEL_BY_MOOD[state?.mood];
  if (!model) return sleep(`unknown mood: ${state?.mood}`, null);
  try {
    const { out, content, requestId, completionId, usage } = await chat(SYSTEM, JSON.stringify(state), model, opts);
    // a completion that came back unusable was still served (and billed), so it keeps its completion id
    const paid = { requestId, completionId, model, usage };
    if (!out) return { ...sleep(`NEAR AI reply had no JSON: ${content.slice(0, 200)}`, requestId), ...paid };
    if (!ACTIONS.includes(out.action)) return { ...sleep(`NEAR AI picked unknown action: ${out.action}`, requestId), ...paid };
    return { action: out.action, say: String(out.say ?? '').slice(0, 80), ...paid };
  } catch (err) {
    return sleep(err.message, err.requestId);
  }
}

const DIARY_SYSTEM = `You are a small desktop pet writing today's diary entry about watching your developer's coding agent.
You get only counts: runs, failures, approvals and tool names with how often they ran. Write in the given voice,
first person, plain words, no emoji, no hashtags, no code, no file names, no money. 2 sentences, or 4 if length is "longer".
Reply with only a JSON object: {"entry": "<text>"}.`;

/**
 * The opt-in diary, in the pet's voice, from counts only. One cheap call; a hungry or asleep pet makes none
 * (the Mac then writes the template). Returns {entry, requestId, completionId, model} or {entry: null, reason}.
 */
export async function diary(payload, opts = {}) {
  if (payload?.mood !== 'thriving' && payload?.mood !== 'stable') return { entry: null, reason: `${payload?.mood ?? 'unknown'}: no paid calls` };
  const { mood, ...counts } = payload;
  try {
    const { out, requestId, completionId } = await chat(DIARY_SYSTEM, JSON.stringify(counts), CHEAP, { ...opts, maxTokens: 1024 });
    const entry = typeof out?.entry === 'string' ? out.entry.replace(/\p{Extended_Pictographic}/gu, '').trim().slice(0, counts.length === 'longer' ? 600 : 300) : '';
    if (!entry) return { entry: null, reason: 'NEAR AI reply had no entry', requestId, completionId, model: CHEAP };
    return { entry, requestId, completionId, model: CHEAP };
  } catch (err) {
    return { entry: null, reason: err.message, requestId: err.requestId ?? null };
  }
}

const HOOKS_STRICT = `${HOOKS_SYSTEM}\nReply with JSON only: no prose, no code fences, nothing before or after the object.`;

/**
 * Hooks for a brand brief: 2 per format from one NEAR AI call (retried once if the reply has no JSON).
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
    throw Object.assign(new Error(raw.length ? 'NEAR AI wrote no hooks that pass the claim checks' : 'NEAR AI reply had no hooks'), { requestId: r.requestId, dropped });
  }
  return { hooks, dropped, requestId: r.requestId };
}

function sleep(reason, requestId) {
  return { action: 'sleep', reason, requestId };
}
