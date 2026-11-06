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
