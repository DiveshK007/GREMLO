// Deterministic checks on ad copy. The model writes hooks; this decides what may run.
// Rules: no numbers, multipliers, percentages or superlatives the brand did not supply,
// and no return/performance promises for financial products at all.

export const FORMATS = ['humour', 'sarcasm', 'offer', 'question', 'bold-claim', 'urgency', 'story', 'dev-meme'];
export const MAX_HOOK = 80;

// promises of money made: never allowed, whoever supplies them
const FIN_PROMISE = /\b(returns?|profits?|profitable|apy|apr|roi|yields?|gains?|guaranteed|risk[- ]free|get rich|passive income|double your money|to the moon|financial freedom)\b/i;
// financial products: any numeric claim about them reads as a performance promise
const FIN_CONTEXT = /\b(trad(e|es|ing|er)|invest(ing|ment|or)?s?|stocks?|crypto|tokens?|forex|portfolio|hedge|signals?|altcoins?|memecoins?|defi|staking)\b/i;
const SUPERLATIVE = /\b(best|fastest|cheapest|leading|#\s?1|number one|no\.?\s?1|only|unbeatable|world'?s first|first ever|most (?:powerful|advanced|accurate))\b/gi;
const NUMBER = /(?:[$€£₹]\s?)?\d+(?:[.,]\d+)?\s?(?:x\b|×|%|k\b|m\b|b\b)?/gi;
const URL = /(https?:\/\/|www\.|\b[a-z0-9-]+\.(?:com|io|ai|dev|xyz|app|co)\b)/i;
const EMOJI = /\p{Extended_Pictographic}/u;

const norm = (s) => s.toLowerCase().replace(/\s+/g, '').replace(/×/g, 'x').replace(/,/g, '.');
const TIME_OF_DAY = /\b\d{1,2}(?::\d{2})?\s?(?:am|pm)\b/gi; // "2am" sets a scene, it is not a claim
const numbers = (s) => (s.replace(TIME_OF_DAY, '').match(NUMBER) ?? []).map(norm);
const superlatives = (s) => (s.match(SUPERLATIVE) ?? []).map((w) => w.toLowerCase().replace(/\s+/g, ' '));

/** Brand-supplied text the copy may draw claims from. */
const claimSource = (brief) => [brief.proof ?? '', brief.offer ?? ''].join('\n');

/** Rejects a brief that asks for money promises, before any 0G call is spent. Returns a reason or null. */
export function checkBrief(brief) {
  const all = [brief.product, brief.audience, brief.offer, brief.proof, brief.cta].filter(Boolean).join('\n');
  if (FIN_PROMISE.test(all)) return 'Notchi does not run promises of returns, profit or guaranteed gains.';
  if (FIN_CONTEXT.test(all) && numbers(claimSource(brief)).length) {
    return 'Notchi does not run performance numbers for trading, investing or crypto products. Describe what the product does instead.';
  }
  return null;
}

/** Checks one hook against the brief. Returns a reason it was dropped, or null if it may run. */
export function checkHook(text, brief) {
  const t = String(text ?? '').trim();
  if (!t) return 'empty';
  if (t.length > MAX_HOOK) return `longer than ${MAX_HOOK} characters`;
  if (URL.test(t)) return 'contains a link (the sign opens the link itself)';
  if (EMOJI.test(t)) return 'contains emoji';
  if (FIN_PROMISE.test(t)) return 'promises returns or profit';
  const context = [brief.product, brief.audience].filter(Boolean).join(' ');
  if (FIN_CONTEXT.test(context) || FIN_CONTEXT.test(t)) {
    if (numbers(t).length) return 'performance number for a financial product';
  }
  const allowedNums = new Set(numbers(claimSource(brief)));
  const invented = numbers(t).filter((n) => !allowedNums.has(n));
  if (invented.length) return `number not in your proof points: ${invented.join(', ')}`;
  const allowedSup = claimSource(brief).toLowerCase();
  const sup = superlatives(t).filter((w) => !allowedSup.includes(w));
  if (sup.length) return `claim not in your proof points: ${sup.join(', ')}`;
  return null;
}
