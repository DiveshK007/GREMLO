// Pet decisions and ad lines via the 0G Compute Router (OpenAI-compatible). Never invents output:
// think() safe-stops to {action: "sleep", reason}; suggestLines() throws with the real error.

export const ACTIONS = ['wake', 'work', 'wave', 'wait', 'celebrate', 'sad', 'go_home', 'sleep'];

const SYSTEM = `You are Notchi, a small desktop pet that watches a coding agent.
Given the pet state as JSON, pick one action from: ${ACTIONS.join(', ')}.
Reply with only a JSON object: {"action": "<one action>", "say": "<at most 8 words>"}.`;

/** Tones a brand can pick for its hooks; the value is what the model is told. */
export const TONES = {
  bold: 'confident and punchy',
  calm: 'plain and understated',
  'dev-meme': 'developer in-joke humour that still says what the product does',
};

const linesSystem = (tone) => `You write sponsored lines a small desktop pet holds on a sign while a coding agent works.
Given a brand brief, write 3 different lines, each at most 40 characters, plain and specific, no emoji.${tone ? `\nTone: ${TONES[tone]}.` : ''}
Reply with only a JSON object: {"lines": ["...", "...", "..."]}.`;

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
        max_tokens: 1024, // reasoning models spend tokens before content; too low returns empty
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

const linesStrict = (tone) => `${linesSystem(tone)}\nReply with JSON only: no prose, no code fences, nothing before or after the object.`;

/** Plain-text fallback: only lines the model actually wrote (list markers and quotes stripped), never filler. */
export function linesFromText(text) {
  return text.split('\n')
    .filter((raw) => !/"\s*:/.test(raw)) // a JSON key, not a line
    .map((raw) => raw.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, '').replace(/^["'`“”]+|["'`“”]+$/g, '').trim())
    .filter((l) => l && l.length <= 80 && !l.endsWith(':') && !/^[{}[\]`]/.test(l) && !/^(here|sure|okay|certainly)\b/i.test(l))
    .slice(0, 3);
}

/**
 * Ad lines from the smart model. A reply with no JSON is retried once with a stricter instruction; if that
 * still has no JSON, up to 3 lines are taken from its plain text. Lines carry the request ID of the call
 * they came from. Nothing is ever made up: no usable lines means a throw with the real request ID.
 */
export async function suggestLines(brief, opts = {}) {
  opts = { timeoutMs: 60000, ...opts }; // live call took 33s
  if (opts.tone !== undefined && !Object.hasOwn(TONES, opts.tone)) throw new Error(`unknown tone: ${opts.tone}`);
  let r = await chat(linesSystem(opts.tone), String(brief), SMART, opts);
  if (!r.out) r = await chat(linesStrict(opts.tone), String(brief), SMART, opts);
  const lines = r.out
    ? (Array.isArray(r.out.lines) ? r.out.lines.filter((l) => typeof l === 'string' && l.trim()).slice(0, 3) : [])
    : linesFromText(r.content);
  const enough = r.out ? lines.length === 3 : lines.length >= 1; // JSON must give all 3; plain text gives what it has
  if (!enough || !r.requestId) throw Object.assign(new Error(r.out ? '0G reply did not have 3 lines' : '0G reply had no usable lines'), { requestId: r.requestId });
  return lines.map((l) => ({ text: l.trim().slice(0, 80), requestId: r.requestId }));
}

function sleep(reason, requestId) {
  return { action: 'sleep', reason, requestId };
}
