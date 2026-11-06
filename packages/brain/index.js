// Pet decisions and ad lines via the 0G Compute Router (OpenAI-compatible). Never invents output:
// think() safe-stops to {action: "sleep", reason}; suggestLines() throws with the real error.

export const ACTIONS = ['wake', 'work', 'wave', 'wait', 'celebrate', 'sad', 'go_home', 'sleep'];

const SYSTEM = `You are Notchi, a small desktop pet that watches a coding agent.
Given the pet state as JSON, pick one action from: ${ACTIONS.join(', ')}.
Reply with only a JSON object: {"action": "<one action>", "say": "<at most 8 words>"}.`;

const LINES_SYSTEM = `You write sponsored lines a small desktop pet holds on a sign while a coding agent works.
Given a brand brief, write 3 different lines, each at most 60 characters, plain and specific, no emoji.
Reply with only a JSON object: {"lines": ["...", "...", "..."]}.`;

const SMART = process.env.ZG_MODEL_SMART || process.env.ZG_MODEL;
const CHEAP = process.env.ZG_MODEL_CHEAP || process.env.ZG_MODEL;
if (!SMART || !CHEAP) {
  throw new Error('brain: set ZG_MODEL_SMART and ZG_MODEL_CHEAP (or ZG_MODEL as fallback for both) in .env');
}
export const MODEL_BY_MOOD = { thriving: SMART, stable: CHEAP, hungry: CHEAP };

/** One router call. Returns the parsed JSON object from the reply; throws Error with .requestId on any failure. */
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
  if (!out) throw fail(`0G reply had no JSON: ${content.slice(0, 200)}`);
  return { out, requestId, cost: data.x_0g_trace?.billing?.total_cost ?? null };
}

export async function think(state, opts = {}) {
  if (state?.mood === 'asleep') return sleep('asleep: no paid calls', null);
  const model = MODEL_BY_MOOD[state?.mood];
  if (!model) return sleep(`unknown mood: ${state?.mood}`, null);
  try {
    const { out, requestId, cost } = await chat(SYSTEM, JSON.stringify(state), model, opts);
    if (!ACTIONS.includes(out.action)) return sleep(`0G picked unknown action: ${out.action}`, requestId);
    return { action: out.action, say: String(out.say ?? '').slice(0, 80), requestId, cost };
  } catch (err) {
    return sleep(err.message, err.requestId);
  }
}

/** 3 ad lines from one smart-model call. All three carry that call's real request ID. */
export async function suggestLines(brief, opts = {}) {
  const { out, requestId } = await chat(LINES_SYSTEM, String(brief), SMART, opts);
  const lines = Array.isArray(out.lines) ? out.lines.filter((l) => typeof l === 'string' && l.trim()).slice(0, 3) : [];
  if (lines.length !== 3 || !requestId) throw Object.assign(new Error('0G reply did not have 3 lines'), { requestId });
  return lines.map((l) => ({ text: l.trim().slice(0, 80), requestId }));
}

function sleep(reason, requestId) {
  return { action: 'sleep', reason, requestId };
}
