import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkBrief, checkHook } from './claims.js';

const brief = {
  product: 'Clearlog, log search for TypeScript teams',
  audience: 'backend developers',
  offer: 'first 1M logs free',
  proof: 'Indexes 1M logs in 30 seconds\nUsed by 40 teams',
  cta: 'Try it free',
};

test('hooks may reuse the brand\'s own numbers', () => {
  assert.equal(checkHook('1M logs searched in 30 seconds. Seriously.', brief), null);
  assert.equal(checkHook('40 teams stopped grepping. Your turn?', brief), null);
  assert.equal(checkHook('First 1M logs free. Your future self says thanks.', brief), null);
});

test('invented numbers, multipliers and percentages are dropped', () => {
  assert.match(checkHook('Search logs 10x faster', brief), /not in your proof points: 10x/);
  assert.match(checkHook('Cut debugging time by 50%', brief), /50%/);
  assert.match(checkHook('Trusted by 500 teams', brief), /500/);
});

test('superlatives need the brand\'s own backing', () => {
  assert.match(checkHook('The fastest log search on earth', brief), /fastest/);
  assert.match(checkHook('The only log tool you need', brief), /only/);
  assert.equal(checkHook('Fastest way to find that one log line', { ...brief, proof: 'fastest log search in our benchmark' }), null);
});

test('financial return promises are never allowed, even when the brand supplies them', () => {
  const bot = { product: 'an AI trading bot', audience: 'crypto traders', proof: 'hit 20x in 5 days', cta: 'Know more' };
  assert.match(checkBrief(bot), /performance numbers for trading/);
  assert.match(checkHook('This AI trading bot hit 20x in 5 days. Know more', bot), /financial product/);
  assert.match(checkBrief({ product: 'a savings app', proof: 'guaranteed 12% APY' }), /returns, profit/);
  assert.match(checkHook('Guaranteed profit while you code', brief), /promises returns/);
  // a trading tool can still say what it does
  assert.equal(checkHook('Backtest strategies in plain English. Try it free', { ...bot, proof: '' }), null);
});

test('format rules: length, links, emoji', () => {
  assert.match(checkHook('x'.repeat(81), brief), /longer than 80/);
  assert.match(checkHook('Try clearlog.dev today', brief), /link/);
  assert.match(checkHook('Logs, sorted 🔥', brief), /emoji/);
  assert.equal(checkBrief(brief), null);
});
