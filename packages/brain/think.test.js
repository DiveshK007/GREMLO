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

const BRIEF = { product: 'Clearlog, log search for TypeScript teams', audience: 'backend developers', offer: 'first 1M logs free', proof: 'Indexes 1M logs in 30 seconds', cta: 'Try it free' };
const turn = (content, id) => new Response(JSON.stringify({ choices: [{ message: { content } }], x_0g_trace: { request_id: id } }));
const hooksJson = (list) => JSON.stringify({ hooks: list.map(([format, text]) => ({ format, text })) });

test('suggestHooks keeps hooks that pass the claim checks and reports the rest with reasons', async () => {
  const { suggestHooks } = await import('./index.js');
  const sent = [];
  const fetch = async (u, init) => {
    const body = JSON.parse(init.body); sent.push(body);
    return turn(hooksJson([
      ['humour', 'Your logs called. They want to be found. Try it free'],
      ['bold-claim', 'Indexes 1M logs in 30 seconds'],
      ['bold-claim', 'Search logs 10x faster'],             // invented multiplier
      ['offer', 'First 1M logs free. Yes, free.'],
      ['offer', 'The best log tool ever'],                   // invented superlative
      ['offer', 'First 1M logs free, no card needed'],
      ['offer', 'First 1M logs free. Grep less.'],           // a third offer hook: capped at 2
      ['nonsense', 'ignored format'],
    ]), 'H1');
  };
  const r = await suggestHooks(BRIEF, { fetch });
  assert.equal(r.requestId, 'H1');
  assert.deepEqual(r.hooks.map((h) => h.format), ['humour', 'bold-claim', 'offer', 'offer']);
  assert.ok(r.hooks.every((h) => h.requestId === 'H1'));
  assert.deepEqual(r.dropped.map((d) => d.reason), ['number not in your proof points: 10x', 'claim not in your proof points: best']);
  // the prompt carries the rules and the brief, on the smart model with room to think
  assert.match(sent[0].messages[0].content, /Never invent statistics/);
  assert.match(sent[0].messages[0].content, /Never promise money, returns, profit or gains/);
  assert.match(sent[0].messages[1].content, /Indexes 1M logs in 30 seconds/);
  assert.equal(sent[0].model, 'smart-model');
  assert.equal(sent[0].max_tokens, 8192);
});

test('suggestHooks refuses financial-return briefs before spending a 0G call', async () => {
  const { suggestHooks } = await import('./index.js');
  let called = false;
  const fetch = async () => { called = true; return turn('{}', 'X'); };
  await assert.rejects(suggestHooks({ product: 'an AI trading bot', audience: 'traders', proof: 'hit 20x in 5 days', cta: 'Know more' }, { fetch }), /performance numbers for trading/);
  assert.equal(called, false);
});

test('suggestHooks retries once for JSON and never invents hooks', async () => {
  const { suggestHooks } = await import('./index.js');
  const queue = (...replies) => ({ n: 0, fetch: async () => replies.shift() });
  let q = queue(turn('Sure! Here are some hooks', 'A1'), turn(hooksJson([['question', 'Still grepping logs at 2am? Try it free']]), 'A2'));
  assert.deepEqual((await suggestHooks(BRIEF, { fetch: q.fetch })).hooks, [{ format: 'question', text: 'Still grepping logs at 2am? Try it free', requestId: 'A2' }]);
  q = queue(turn('no json', 'B1'), turn('still none', 'B2'));
  await assert.rejects(suggestHooks(BRIEF, { fetch: q.fetch }), (e) => /no hooks/.test(e.message) && e.requestId === 'B2');
  q = queue(turn(hooksJson([['bold-claim', 'Trusted by 900 teams']]), 'C1'));
  await assert.rejects(suggestHooks(BRIEF, { fetch: q.fetch }), (e) => /pass the claim checks/.test(e.message) && e.dropped.length === 1);
  await assert.rejects(suggestHooks(BRIEF, { fetch: async () => new Response('{"error":"insufficient balance"}', { status: 402 }) }), /402/);
});

test('think leaves the reasoning model room to answer', async () => {
  const caps = [];
  const fetch = async (u, init) => { caps.push(JSON.parse(init.body).max_tokens); return turn('{"action":"work"}', 'M1'); };
  await think({ mood: 'stable' }, { fetch });
  assert.deepEqual(caps, [2048]);
});
