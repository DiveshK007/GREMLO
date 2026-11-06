// Pet decisions via the 0G Compute Router (OpenAI-compatible). Never invents a decision:
// any failure returns {action: "sleep", reason} with the real error text.

export const ACTIONS = ['wake', 'work', 'wave', 'wait', 'celebrate', 'sad', 'go_home', 'sleep'];

const SYSTEM = `You are Notchi, a small desktop pet that watches a coding agent.
Given the pet state as JSON, pick one action from: ${ACTIONS.join(', ')}.
Reply with only a JSON object: {"action": "<one action>", "say": "<at most 8 words>"}.`;

export async function think(state, opts = {}) {
  const base = opts.base ?? process.env.ZG_API_BASE ?? 'https://router-api.0g.ai/v1';
  const key = opts.key ?? process.env.ZG_API_KEY ?? '';
  // shortcut: one fixed model, mood tiers should pass opts.model once balance reads exist
  const model = opts.model ?? process.env.ZG_MODEL ?? 'glm-5.2';
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
