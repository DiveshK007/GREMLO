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
  assert.equal(checkHook('1M logs searched in 30 seconds', brief), null);
  assert.equal(checkHook('40 teams stopped grepping. Your turn?', brief), null);
  assert.equal(checkHook('First 1M logs free. You\'re welcome.', brief), null);
});

test('invented numbers, multipliers and percentages are dropped', () => {
  assert.match(checkHook('Search logs 10x faster', brief), /not in your proof points: 10x/);
  assert.match(checkHook('Cut debugging time by 50%', brief), /50%/);
  assert.match(checkHook('Trusted by 500 teams', brief), /500/);
  // a time of day is scene-setting, not a claim
  assert.equal(checkHook('Still grepping logs at 2am? Try it free', brief), null);
});

test('superlatives need the brand\'s own backing', () => {
  assert.match(checkHook('The fastest log search on earth', brief), /fastest/);
  assert.match(checkHook('The only log tool you need', brief), /only/);
  assert.equal(checkHook('Fastest way to find that one log line', { ...brief, proof: 'fastest log search in our benchmark' }), null);
});

test('financial return promises are never allowed, even when the brand supplies them', () => {
  const bot = { product: 'an AI trading bot', audience: 'crypto traders', proof: 'hit 20x in 5 days', cta: 'Know more' };
  assert.match(checkBrief(bot), /performance numbers for trading/);
  assert.match(checkHook('This bot hit 20x in 5 days', bot), /financial product/);
  assert.match(checkBrief({ product: 'a savings app', proof: 'guaranteed 12% APY' }), /returns, profit/);
  assert.match(checkHook('Guaranteed profit while you code', brief), /promises returns/);
  // a trading tool can still say what it does
  assert.equal(checkHook('Backtest in plain English', { ...bot, proof: '' }), null);
});

test('format rules: length, links, emoji', () => {
  assert.match(checkHook('x'.repeat(41), brief), /longer than 40/);
  assert.match(checkHook('Logs', brief), /shorter than 6/);
  assert.equal(checkHook('Logs, found. Try it free', brief), null);
  assert.match(checkHook('Try clearlog.dev today', brief), /link/);
  assert.match(checkHook('Logs, sorted 🔥', brief), /emoji/);
  assert.equal(checkBrief(brief), null);
});

test('closed categories never run (R2 §15)', () => {
  assert.match(checkHook('Bet now on tonight', brief), /gambling/);
  assert.match(checkHook('Join the presale early', brief), /speculative/);
  assert.match(checkHook('Vote for better logs', brief), /political/);
  assert.match(checkBrief({ ...brief, product: 'Online casino for devs' }), /gambling/);
  assert.equal(checkHook('Ship faster, sleep more', brief), null);
});
