// Phone and Watch relay: a mailbox per pairing holding sealed boxes the server can't read (AES-GCM, key shared
// by QR code between the Mac and the phone). The latest state from the Mac, and answers from the phone.

const bad = (m: string) => Object.assign(new Error(m), { status: 400 });
export type Mailbox = { state: string | null; answers: string[]; seen: number };
export const BOX_MAX = 16_000, ANSWERS_MAX = 20, MAILBOX_TTL_MS = 24 * 3_600_000;

export function channel(c: string) { if (!/^[a-f0-9]{32}$/.test(c)) throw bad("bad channel"); return c; }
export function box(b: any) {
  const s = String(b?.box ?? "");
  if (!s || s.length > BOX_MAX || !/^[A-Za-z0-9+/=]+$/.test(s)) throw bad("box must be base64, at most 16 KB");
  return s;
}
export function prune(m: Record<string, Mailbox>, now: number) { for (const [k, v] of Object.entries(m)) if (now - v.seen > MAILBOX_TTL_MS) delete m[k]; }
export function putState(m: Record<string, Mailbox>, c: string, b: any, now: number) {
  const mb = (m[channel(c)] ??= { state: null, answers: [], seen: now });
  mb.state = box(b); mb.seen = now;
  return { ok: true };
}
export function getState(m: Record<string, Mailbox>, c: string) { return { box: m[channel(c)]?.state ?? null }; }
export function addAnswer(m: Record<string, Mailbox>, c: string, b: any, now: number) {
  const mb = m[channel(c)];
  if (!mb) throw Object.assign(new Error("no Mac on this pairing"), { status: 404 });
  mb.answers = [...mb.answers, box(b)].slice(-ANSWERS_MAX);
  return { ok: true };
}
export function takeAnswers(m: Record<string, Mailbox>, c: string, now: number) {
  const mb = m[channel(c)];
  if (!mb) return { boxes: [] };
  mb.seen = now;
  const out = mb.answers; mb.answers = [];
  return { boxes: out };
}
