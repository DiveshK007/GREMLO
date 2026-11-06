import { test } from 'node:test';
import assert from 'node:assert/strict';
import { think } from './index.js';

const reply = (status, body) => async () => new Response(JSON.stringify(body), { status });

test('parses action, say and request id', async () => {
  const out = await think({}, { fetch: reply(200, {
    choices: [{ message: { content: '```json\n{"action":"wave","say":"need you"}\n```' } }],
    x_0g_trace: { request_id: 'r1', billing: { total_cost: '5' } },
  }) });
  assert.deepEqual(out, { action: 'wave', say: 'need you', requestId: 'r1', cost: '5' });
});

test('safe-stops on HTTP error, unknown action and network failure', async () => {
  const broke = await think({}, { fetch: reply(402, { error: { message: 'insufficient balance' } }) });
  assert.equal(broke.action, 'sleep');
  assert.match(broke.reason, /402.*insufficient balance/);

  const odd = await think({}, { fetch: reply(200, { choices: [{ message: { content: '{"action":"pay"}' } }] }) });
  assert.equal(odd.action, 'sleep');

  const down = await think({}, { fetch: async () => { throw new Error('ECONNREFUSED'); } });
  assert.deepEqual(down, { action: 'sleep', reason: '0G unreachable: ECONNREFUSED', requestId: null });
});
