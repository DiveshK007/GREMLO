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

/** Rejects with a TimeoutError after `ms` (near-api-js takes no abort signal, so a dead host would hold ~10 s). */
export function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let t: ReturnType<typeof setTimeout>;
  const timer = new Promise<never>((_, reject) => {
    t = setTimeout(() => reject(Object.assign(new Error(`timed out after ${ms} ms`), { name: "TimeoutError" })), ms);
  });
  return Promise.race([p, timer]).finally(() => clearTimeout(t));
}

/**
 * Failover across RPC URLs with a circuit breaker. A URL that fails with a retryable error is skipped for
 * `cooldownMs`; healthy URLs are tried first, starting with the last one that answered (sticky); broken ones are
 * only a last resort. Each call is capped at `timeoutMs`. A non-retryable error is thrown at once, untouched.
 */
export function failover(urls: string[], opts: { backoffMs?: number; cooldownMs?: number; timeoutMs?: number; wait?: (ms: number) => Promise<unknown>; now?: () => number } = {}) {
  if (!urls.length) throw new Error("no RPC URLs");
  let preferred = 0;
  const downUntil = new Map<string, number>();
  const backoff = opts.backoffMs ?? 300, cooldown = opts.cooldownMs ?? 60_000, wait = opts.wait ?? sleep, now = opts.now ?? Date.now;
  const self = {
    get current() { return urls[preferred]; },
    /** Healthy URLs from the preferred one round, then broken ones, soonest to recover first. */
    order() {
      const t = now(), round = urls.map((_, k) => urls[(preferred + k) % urls.length]);
      const healthy = round.filter((u) => (downUntil.get(u) ?? 0) <= t);
      const broken = round.filter((u) => (downUntil.get(u) ?? 0) > t).sort((a, b) => downUntil.get(a)! - downUntil.get(b)!);
      return [...healthy, ...broken];
    },
    ok(url: string) { downUntil.delete(url); preferred = urls.indexOf(url); },
    fail(url: string) { downUntil.set(url, now() + cooldown); },
    async run<T>(call: (url: string) => Promise<T>, timeoutMs = opts.timeoutMs ?? 3_000): Promise<T> {
      const order = self.order();
      let last: unknown;
      for (const [k, url] of order.entries()) {
        try {
          const r = await withTimeout(call(url), timeoutMs);
          self.ok(url);
          return r;
        } catch (e) {
          const tagged = e && typeof e === "object" ? Object.assign(e, { rpcUrl: url }) : e; // which RPC said it
          if (!isRetryable(e)) throw tagged;
          self.fail(url);
          last = tagged;
          if (k < order.length - 1) await wait(backoff * 2 ** k);
        }
      }
      throw last;
    },
  };
  return self;
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
  /** Told about each URL's outcome, so the circuit breaker learns from sends too. */
  ok?: (url: string) => void;
  fail?: (url: string) => void;
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
      const r = await io.send(urls[k]);
      io.ok?.(urls[k]);
      return r;
    } catch (e) {
      if (!isRetryable(e)) throw e;
      io.fail?.(urls[k]);
      last = e;
    }
  }
  throw last;
}
