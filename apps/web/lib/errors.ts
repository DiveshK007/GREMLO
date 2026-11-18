// The vault's refusals (contracts-near require! messages) as sentences. Unlisted ones get the generic line below.
const CONTRACT: [RegExp, string][] = [
  [/deposit must cover storage/, "The budget is too small. It has to cover a one-time storage fee plus at least one view."],
  [/rate must be > 0 and end_time/, "The price per view must be more than 0 and the end time in the future."],
  [/attach the top-up|amount must be > 0/, "Enter an amount to add."],
  [/line_hash must be/, "Your hooks didn't reach the contract intact. Try again."],
  [/NotEnoughStorageDeposit/, "That needs a little more NEAR to cover storage."],
];

/** An error as a person should read it: our server's plain messages pass through, wallet and network noise is replaced. */
export function plainError(e: unknown): string {
  const m = (e instanceof Error ? e.message : String(e ?? "")).split("\n")[0].trim();
  if (/\b(BadParams|NotEnoughStorageDeposit|DuplicateCharge)\b|Smart contract panicked|Transaction \S* failed/.test(m))
    return CONTRACT.find(([re]) => re.test(m))?.[1] ?? "The contract refused this. Nothing was charged except network fees.";
  if (/reject|denied|declined|cancel|closed the (window|popup)|user closed/i.test(m)) return "You closed the wallet before approving.";
  if (!m || /TypeError|ReferenceError|SyntaxError|undefined|\bnull\b|Failed to fetch|NetworkError|JSON|at https?:|\bat \w+\./i.test(m))
    return "Something went wrong on our side. Try again in a minute; if it keeps happening, contact us.";
  return m.length > 200 ? `${m.slice(0, 197)}...` : m;
}
