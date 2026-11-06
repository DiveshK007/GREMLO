// Pet decisions via the 0G Compute Router (OpenAI-compatible). Never invents a decision:
// any failure returns {action: "sleep", reason} with the real error text.

export const ACTIONS = ['wake', 'work', 'wave', 'wait', 'celebrate', 'sad', 'go_home', 'sleep'];

const SYSTEM = `You are Notchi, a small desktop pet that watches a coding agent.
Given the pet state as JSON, pick one action from: ${ACTIONS.join(', ')}.
Reply with only a JSON object: {"action": "<one action>", "say": "<at most 8 words>"}.`;

const SMART = process.env.ZG_MODEL_SMART || process.env.ZG_MODEL;
const CHEAP = process.env.ZG_MODEL_CHEAP || process.env.ZG_MODEL;
if (!SMART || !CHEAP) {
  throw new Error('brain: set ZG_MODEL_SMART and ZG_MODEL_CHEAP (or ZG_MODEL as fallback for both) in .env');
}
export const MODEL_BY_MOOD = { thriving: SMART, stable: CHEAP, hungry: CHEAP };

export async function think(state, opts = {}) {
  if (state?.mood === 'asleep') return sleep('asleep: no paid calls', null);
  const model = MODEL_BY_MOOD[state?.mood];
  if (!model) return sleep(`unknown mood: ${state?.mood}`, null);

  const base = opts.base ?? process.env.ZG_API_BASE ?? 'https://router-api.0g.ai/v1';
  const key = opts.key ?? process.env.ZG_API_KEY ?? '';
  const doFetch = opts.fetch ?? fetch;
  let requestId = null;

  try {
    const res = await doFetch(`${base}/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: SYSTEM },
          { role: 'user', content: JSON.stringify(state) },
        ],
        max_tokens: 1024, // reasoning models spend tokens before content; too low returns empty
      }),
      signal: AbortSignal.timeout(opts.timeoutMs ?? 20000),
    });
    const text = await res.text();
    let data = null;
    try { data = JSON.parse(text); } catch {}
    requestId = data?.x_0g_trace?.request_id ?? res.headers.get('x-request-id') ?? null;
    if (!res.ok) return sleep(`0G HTTP ${res.status}: ${text.slice(0, 300)}`, requestId);

    const content = data?.choices?.[0]?.message?.content ?? '';
    const match = content.match(/\{[\s\S]*\}/);
    if (!match) return sleep(`0G reply had no JSON: ${content.slice(0, 200)}`, requestId);
    const out = JSON.parse(match[0]);
    if (!ACTIONS.includes(out.action)) return sleep(`0G picked unknown action: ${out.action}`, requestId);
    return { action: out.action, say: String(out.say ?? '').slice(0, 80), requestId, cost: data.x_0g_trace?.billing?.total_cost ?? null };
  } catch (err) {
    return sleep(`0G unreachable: ${err.message}`, requestId);
  }
}

function sleep(reason, requestId) {
  return { action: 'sleep', reason, requestId };
}
