// The team relay (visits between teammates) and the pairing channel to a phone or Watch.

import { type IncomingMessage } from "node:http";
import { allow } from "../batch.ts";
import { HttpError } from "../register.ts";
import { pruneHits } from "../prune.ts";
import { relayInbox, relayJoin, relaySend } from "../social.ts";
import { addAnswer, getState, prune as prunePhones, putState, takeAnswers } from "../phone.ts";
import { type Loose } from "../json.ts";
import { NOT_HANDLED, type Url, readBody, save, store } from "../state.ts";

const phoneHits = new Map<string, number[]>(); // per pairing channel; kept in memory, not saved

/** The relay and phone-channel routes, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname, searchParams }: Url): Promise<Loose> {
  const m = req.method;
  if (m === "POST" && pathname === "/relay/join") return relayJoin(store.relay, await readBody(req), Date.now());
  if (m === "POST" && pathname === "/relay/visit") {
    const r = relaySend(store.relay, await readBody(req), Date.now());
    save();
    return r;
  }
  if (m === "POST" && pathname === "/relay/inbox") {
    // delivering marks visits as delivered, so it is a POST (the GET stays one release)
    const b = await readBody(req);
    const r = relayInbox(store.relay, new URLSearchParams({ team: String(b?.team ?? ""), handle: String(b?.handle ?? "") }), Date.now());
    save();
    return { visits: r };
  }
  if (m === "GET" && pathname === "/relay/inbox") {
    const r = relayInbox(store.relay, searchParams, Date.now());
    save();
    return { visits: r };
  }
  const phone = pathname.match(/^\/phone\/([a-f0-9]{32})\/(state|answers)$/);
  if (phone) {
    const [, ch, what] = phone,
      now = Date.now();
    prunePhones(store.phones, now);
    if (!allow(phoneHits, ch, now, 3600, 3_600_000)) throw new HttpError(429, "slow down");
    if (what === "state") return m === "PUT" ? putState(store.phones, ch, await readBody(req), now) : getState(store.phones, ch);
    return m === "POST" ? addAnswer(store.phones, ch, await readBody(req), now) : takeAnswers(store.phones, ch, now);
  }
  return NOT_HANDLED;
}

export function housekeeping(now: number) {
  pruneHits(phoneHits, now, 86_400_000);
}
