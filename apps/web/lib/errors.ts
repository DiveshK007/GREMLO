/** An error as a person should read it: our server's plain messages pass through, wallet and network noise is replaced. */
export function plainError(e: unknown): string {
  const m = (e instanceof Error ? e.message : String(e ?? "")).split("\n")[0].trim();
  if (/reject|denied|declined|cancel|closed the (window|popup)|user closed/i.test(m)) return "You closed the wallet before approving.";
  if (!m || /TypeError|ReferenceError|SyntaxError|undefined|\bnull\b|Failed to fetch|NetworkError|JSON|at https?:|\bat \w+\./i.test(m))
    return "Something went wrong on our side. Try again in a minute; if it keeps happening, contact us.";
  return m.length > 200 ? `${m.slice(0, 197)}...` : m;
}
