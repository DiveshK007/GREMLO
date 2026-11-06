import { test } from 'node:test';
import assert from 'node:assert/strict';

// set before import: index.js reads model env at load
process.env.ZG_MODEL_SMART = 'smart-model';
process.env.ZG_MODEL_CHEAP = 'cheap-model';
const { think } = await import('./index.js');

const reply = (status, body) => async () => new Response(JSON.stringify(body), { status });
const ok = reply(200, { choices: [{ message: { content: '{"action":"work","say":"on it"}' } }], x_0g_trace: { request_id: 'r' } });

test('parses action, say and request id', async () => {
  const out = await think({ mood: 'stable' }, { fetch: reply(200, {
    choices: [{ message: { content: '```json\n{"action":"wave","say":"need you"}\n```' } }],
    x_0g_trace: { request_id: 'r1', billing: { total_cost: '5' } },
  }) });
  assert.deepEqual(out, { action: 'wave', say: 'need you', requestId: 'r1', cost: '5' });
});

test('picks the model by mood, no call when asleep', async () => {
  const sent = [];
  const spy = async (url, init) => { sent.push(JSON.parse(init.body).model); return ok(); };
  await think({ mood: 'thriving' }, { fetch: spy });
  await think({ mood: 'stable' }, { fetch: spy });
  await think({ mood: 'hungry' }, { fetch: spy });
  assert.deepEqual(sent, ['smart-model', 'cheap-model', 'cheap-model']);

  const asleep = await think({ mood: 'asleep' }, { fetch: spy });
  assert.equal(asleep.action, 'sleep');
  assert.equal(sent.length, 3);
});

test('safe-stops on HTTP error, unknown action and network failure', async () => {
  const broke = await think({ mood: 'stable' }, { fetch: reply(402, { error: { message: 'insufficient balance' } }) });
  assert.equal(broke.action, 'sleep');
  assert.match(broke.reason, /402.*insufficient balance/);

  const odd = await think({ mood: 'stable' }, { fetch: reply(200, { choices: [{ message: { content: '{"action":"pay"}' } }] }) });
  assert.equal(odd.action, 'sleep');

  const down = await think({ mood: 'stable' }, { fetch: async () => { throw new Error('ECONNREFUSED'); } });
  assert.deepEqual(down, { action: 'sleep', reason: '0G unreachable: ECONNREFUSED', requestId: null });
});

test('suggestLines returns 3 lines with the real request id, throws otherwise', async () => {
  const { suggestLines } = await import('./index.js');
  const sent = [];
  const lines = await suggestLines('fast CI', { fetch: async (u, init) => { sent.push(JSON.parse(init.body).model); return new Response(JSON.stringify({
    choices: [{ message: { content: '{"lines":["One","Two","Three"]}' } }], x_0g_trace: { request_id: 'L1' },
  })); } });
  assert.deepEqual(lines, [{ text: 'One', requestId: 'L1' }, { text: 'Two', requestId: 'L1' }, { text: 'Three', requestId: 'L1' }]);
  assert.deepEqual(sent, ['smart-model']);

  await assert.rejects(suggestLines('x', { fetch: reply(200, { choices: [{ message: { content: '{"lines":["only one"]}' } }], x_0g_trace: { request_id: 'L2' } }) }), /3 lines/);
  await assert.rejects(suggestLines('x', { fetch: reply(402, { error: 'insufficient balance' }) }), /402/);
});

test('suggestLines retries once for JSON, then falls back to the reply text, never inventing lines', async () => {
  const { suggestLines } = await import('./index.js');
  const turn = (content, id) => new Response(JSON.stringify({ choices: [{ message: { content } }], x_0g_trace: { request_id: id } }));
  const queue = (...replies) => {
    const sent = [];
    return { sent, fetch: async (u, init) => { sent.push(JSON.parse(init.body).messages[0].content); return replies.shift(); } };
  };

  // no JSON, then the stricter retry gives JSON: those lines, with the retry's request id
  let q = queue(turn('Sure, here you go!', 'A1'), turn('{"lines":["One","Two","Three"]}', 'A2'));
  assert.deepEqual((await suggestLines('x', { fetch: q.fetch })).map((l) => l.requestId), ['A2', 'A2', 'A2']);
  assert.equal(q.sent.length, 2);
  assert.match(q.sent[1], /JSON only/);

  // still no JSON: up to 3 lines from the retry's text; preamble, markers and quotes dropped, a 4th ignored
  q = queue(turn('prose', 'B1'), turn('Here are your lines:\n1. Ship faster\n2. "Fewer red builds"\n- Cache it all\n4. One too many', 'B2'));
  assert.deepEqual(await suggestLines('x', { fetch: q.fetch }), [
    { text: 'Ship faster', requestId: 'B2' }, { text: 'Fewer red builds', requestId: 'B2' }, { text: 'Cache it all', requestId: 'B2' },
  ]);

  // nothing usable in the text: throws, carrying the real request id
  q = queue(turn('Here you go:', 'C1'), turn('Sorry:', 'C2'));
  await assert.rejects(suggestLines('x', { fetch: q.fetch }), (e) => /no usable lines/.test(e.message) && e.requestId === 'C2');

  // JSON on the first try: no retry
  q = queue(turn('{"lines":["a","b","c"]}', 'D1'));
  await suggestLines('x', { fetch: q.fetch });
  assert.equal(q.sent.length, 1);
});
