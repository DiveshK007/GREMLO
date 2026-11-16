// Pure formatting for /experience. No imports, so node --test can load it.

/** yoctoNEAR (string) to NEAR with exactly 4 decimals, rounded half up, in integer math. */
export function near4(yocto: string | bigint): string {
  const q = (BigInt(yocto) + 5n * 10n ** 19n) / 10n ** 20n;
  return `${q / 10_000n}.${(q % 10_000n).toString().padStart(4, "0")}`;
}

/** "15 Nov, 03:50" in IST; seconds since the epoch in, as the API sends them. */
export const istWhen = (sec: number) =>
  new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Kolkata", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(sec * 1000);

export const shortHash = (h: string) => `${h.slice(0, 8)}…${h.slice(-4)}`;
/** A NEAR AI request id, shortened: "chatcmpl-5132d660…" or "49b3f9ca…7ae7". */
export const shortReq = (id: string) => (id.startsWith("chatcmpl-") ? `${id.slice(0, 17)}…` : shortHash(id).replace(/^(.{8}).*(….{4})$/, "$1$2"));
/** "Qwen/Qwen3.8-27B" to "Qwen3.8-27B". */
export const modelName = (m: string) => m.split("/").pop() ?? m;

/** Split a paid amount by the pet's compute share (basis points): [to developers, to the pet's compute budget]. */
export function split(paid: bigint, shareBps: number): [bigint, bigint] {
  const compute = (paid * BigInt(shareBps)) / 10_000n;
  return [paid - compute, compute];
}
