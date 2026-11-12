import { test } from 'node:test';
import assert from 'node:assert/strict';

// set before import: index.js reads model env at load
process.env.NEAR_AI_MODEL_SMART = 'smart-model';
process.env.NEAR_AI_MODEL_CHEAP = 'cheap-model';
const { think } = await import('./index.js');

const reply = (status, body) => async () => new Response(JSON.stringify(body), { status });
const ok = reply(200, { choices: [{ message: { content: '{"action":"work","say":"on it"}' } }], id: 'chatcmpl-r' });

test('parses action, say, the completion id and usage', async () => {
  const usage = { prompt_tokens: 40, completion_tokens: 12, total_tokens: 52 };
  const out = await think({ mood: 'stable' }, { fetch: async () => new Response(JSON.stringify({
    id: 'chatcmpl-1', choices: [{ message: { content: '```json\n{"action":"wave","say":"need you"}\n```' } }], usage,
  }), { headers: { 'x-request-id': 'trace-1' } }) });
  assert.deepEqual(out, { action: 'wave', say: 'need you', requestId: 'chatcmpl-1', completionId: 'chatcmpl-1', model: 'cheap-model', usage });
});

test('calls NEAR AI Cloud with the bearer key; a failed call carries X-Request-Id', async () => {
  let url, auth;
  const spy = async (u, init) => { url = u; auth = init.headers.Authorization; return new Response('{"error":"no credits"}', { status: 402, headers: { 'x-request-id': 'trace-2' } }); };
  const out = await think({ mood: 'stable' }, { fetch: spy, key: 'k' });
  assert.equal(url, 'https://cloud-api.near.ai/v1/chat/completions');
  assert.equal(auth, 'Bearer k');
  assert.equal(out.requestId, 'trace-2');
  assert.equal(out.completionId, undefined); // nothing was served, so nothing may be charged
  assert.match(out.reason, /NEAR AI HTTP 402/);
});

test('defaults to the NEAR-hosted TEE models', async () => {
  const { execFileSync } = await import('node:child_process');
  const env = { ...process.env, NEAR_AI_MODEL_SMART: '', NEAR_AI_MODEL_CHEAP: '' };
  const js = "const m = (await import('./index.js')).MODEL_BY_MOOD; console.log(m.thriving + ' ' + m.stable)";
  const out = execFileSync(process.execPath, ['--input-type=module', '-e', js], { env, cwd: import.meta.dirname }).toString().trim();
  assert.equal(out, 'deepseek-ai/DeepSeek-V4.1-Flash-1017 Qwen/Qwen3.8-27B');
});

test('picks the model by mood, no call when asleep', async () => {
  const sent = [];
  const spy = async (url, init) => { sent.push(JSON.parse(init.body).model); return ok(); };
  await think({ mood: 'thriving' }, { fetch: spy });
  await think({ mood: 'stable' }, { fetch: spy });
  assert.deepEqual(sent, ['smart-model', 'cheap-model']);

  for (const mood of ['hungry', 'asleep']) {
    const r = await think({ mood }, { fetch: spy });
    assert.deepEqual([r.action, r.requestId, r.completionId], ['sleep', null, undefined]);
  }
  assert.equal(sent.length, 2);
});

test('safe-stops on HTTP error, unknown action and network failure', async () => {
  const broke = await think({ mood: 'stable' }, { fetch: reply(402, { error: { message: 'insufficient balance' } }) });
  assert.equal(broke.action, 'sleep');
  assert.match(broke.reason, /402.*insufficient balance/);

  const odd = await think({ mood: 'stable' }, { fetch: reply(200, { id: 'chatcmpl-odd', choices: [{ message: { content: '{"action":"pay"}' } }] }) });
  assert.equal(odd.action, 'sleep');
  assert.equal(odd.completionId, 'chatcmpl-odd'); // served and billed, so it is charged too

  const down = await think({ mood: 'stable' }, { fetch: async () => { throw new Error('ECONNREFUSED'); } });
  assert.deepEqual(down, { action: 'sleep', reason: 'NEAR AI unreachable (cloud-api.near.ai): ECONNREFUSED', requestId: null });

  // undici's bare "fetch failed" carries the real reason in .cause; the log must show it
  const dns = await think({ mood: 'stable' }, { fetch: async () => { throw Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('getaddrinfo ENOTFOUND cloud-api.near.ai'), { code: 'ENOTFOUND' }) }); } });
  assert.equal(dns.reason, 'NEAR AI unreachable (cloud-api.near.ai): fetch failed: ENOTFOUND: getaddrinfo ENOTFOUND cloud-api.near.ai');
});

const BRIEF = { product: 'Clearlog, log search for TypeScript teams', audience: 'backend developers', offer: 'first 1M logs free', proof: 'Indexes 1M logs in 30 seconds', cta: 'Try it free' };
const turn = (content, id) => new Response(JSON.stringify({ choices: [{ message: { content } }], id }));
const hooksJson = (list) => JSON.stringify({ hooks: list.map(([format, text]) => ({ format, text })) });

test('suggestHooks keeps hooks that pass the claim checks and reports the rest with reasons', async () => {
  const { suggestHooks } = await import('./index.js');
  const sent = [];
  const fetch = async (u, init) => {
    const body = JSON.parse(init.body); sent.push(body);
    return turn(hooksJson([
      ['humour', 'Your logs called. Try it free'],
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

test('suggestHooks refuses financial-return briefs before spending an AI call', async () => {
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

test('diary: counts in, one cheap call, no call when hungry', async () => {
  const { diary } = await import('./index.js');
  const sent = [];
  const fetch = async (u, init) => { sent.push(JSON.parse(init.body)); return turn(JSON.stringify({ entry: 'I watched 3 runs. Edit was busy today.' }), 'D1'); };
  const r = await diary({ mood: 'stable', species: 'bean', voice: 'plain', runs: 3, failures: 0, approvals: 1, tools: { Edit: 12 }, length: 'short' }, { fetch });
  assert.equal(r.entry, 'I watched 3 runs. Edit was busy today.');
  assert.equal(r.requestId, 'D1');
  assert.equal(sent[0].model, 'cheap-model');
  assert.ok(!sent[0].messages[1].content.includes('mood'), 'the model gets counts, not the money state');
  const none = await diary({ mood: 'hungry', runs: 3 }, { fetch });
  assert.equal(none.entry, null);
  assert.equal(sent.length, 1);
});
