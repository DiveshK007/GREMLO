import { errText } from "./register.ts";

// RPC resilience with no NEAR imports, so it is unit-tested on its own: a short view cache that turns N pollers into
// one call, failover across RPC URLs on rate limits and timeouts, and a broadcast that never sends a tx twice.

/** Comma-separated RPC URLs from env; empty or unset means the defaults. */
export const parseUrls = (v: string | undefined, defaults: string[]) => {
  const urls = (v ?? "").split(",").map((u) => u.trim()).filter(Boolean);
  return urls.length ? urls : defaults;
};

/**
 * Results live `ttlMs` after they settle; while a read is in flight every caller shares it. Failures are not cached,
 * so the next caller tries again.
 */
export function viewCache(ttlMs: number, now = Date.now) {
  const entries = new Map<string, { p: Promise<unknown>; settledAt?: number }>();
  return {
    get<T>(key: string, load: () => Promise<T>): Promise<T> {
      const hit = entries.get(key);
      if (hit && (hit.settledAt === undefined || now() - hit.settledAt < ttlMs)) return hit.p as Promise<T>;
      const entry: { p: Promise<unknown>; settledAt?: number } = { p: Promise.resolve() };
      entry.p = load().then(
        (v) => { entry.settledAt = now(); return v; },
        (e) => { if (entries.get(key) === entry) entries.delete(key); throw e; },
      );
      entries.set(key, entry);
      return entry.p as Promise<T>;
    },
    /** After a write, so the next read sees the new state. */
    clear: () => entries.clear(),
  };
}

/** Worth trying another RPC: rate limits, timeouts, resets, DNS and 5xx. A contract error or a missing account is not. */
export const isRetryable = (e: unknown) =>
  /\b429\b|too many requests|rate.?limit|ETIMEDOUT|ECONNRESET|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|UND_ERR|timed? ?out|TimeoutError|AbortError|fetch failed|\b50[234]\b|bad gateway|service unavailable/i.test(errText(e));

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Runs `call` on the preferred URL; on a retryable error waits (backoff, doubling) and tries the next URL, once
 * each. The URL that answered stays preferred. A non-retryable error is thrown at once, untouched.
 */
export function failover(urls: string[], opts: { backoffMs?: number; wait?: (ms: number) => Promise<unknown> } = {}) {
  if (!urls.length) throw new Error("no RPC URLs");
  let preferred = 0;
  const backoff = opts.backoffMs ?? 400, wait = opts.wait ?? sleep;
  return {
    get current() { return urls[preferred]; },
    async run<T>(call: (url: string) => Promise<T>): Promise<T> {
      let last: unknown;
      for (let k = 0; k < urls.length; k++) {
        const i = (preferred + k) % urls.length;
        try {
          const r = await call(urls[i]);
          preferred = i;
          return r;
        } catch (e) {
          const tagged = e && typeof e === "object" ? Object.assign(e, { rpcUrl: urls[i] }) : e; // which RPC said it
          if (!isRetryable(e)) throw tagged;
          last = tagged;
          if (k < urls.length - 1) await wait(backoff * 2 ** k);
        }
      }
      throw last;
    },
  };
}

/**
 * Sends one already-signed tx. On a retryable failure it asks the next RPC whether the chain has the tx (by hash)
 * before sending the same signed bytes again, so a tx that landed behind a timeout is never sent twice. Identical
 * bytes can't execute twice anyway (same nonce), so this is belt and braces.
 */
export async function broadcastOnce<R>(urls: string[], io: {
  send: (url: string) => Promise<R>;
  /** The tx outcome if this RPC knows the hash, else null. */
  status: (url: string) => Promise<R | null>;
  wait?: (ms: number) => Promise<unknown>;
  backoffMs?: number;
}) {
  const wait = io.wait ?? sleep, backoff = io.backoffMs ?? 400;
  let last: unknown;
  for (let k = 0; k < urls.length; k++) {
    try {
      if (k > 0) {
        await wait(backoff * 2 ** (k - 1));
        const seen = await io.status(urls[k]).catch((e) => { if (isRetryable(e)) return null; throw e; });
        if (seen) return seen;
      }
      return await io.send(urls[k]);
    } catch (e) {
      if (!isRetryable(e)) throw e;
      last = e;
    }
  }
  throw last;
}
