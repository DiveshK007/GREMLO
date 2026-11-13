import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign, verify, createPublicKey } from "node:crypto";
import { addMoment, anonPet, appendEntry, momentTags, momentView, pausedLines, verifyLog, type LogEntry, type MomentBucket } from "./trust.ts";
import { canonical } from "./auth.ts";
import { parkList, parkPet, relayInbox, relayJoin, relaySend, type Park, type Relay } from "./social.ts";
import { checkSubmission, pngSize, report, type Submission } from "./gallery.ts";

test("moments: unknown tags are any; brands see a bucket only with 50 distinct pets", () => {
  assert.deepEqual(momentTags(["tests", "bogus"], 3), ["tests", "any", "any"]);
  const b: Record<string, MomentBucket> = {};
  for (let i = 0; i < 49; i++) addMoment(b, "tests", `pet${i}`);
  addMoment(b, "tests", "pet0");
  assert.deepEqual(momentView(b), { tests: null });
  addMoment(b, "tests", "pet49");
  assert.deepEqual(momentView(b), { tests: 51 });
});

test("3 reports per 1,000 sightings pause a line", () => {
  assert.deepEqual(pausedLines([3, 2, 4], [1000, 10, 2000]), [0]);
  assert.deepEqual(pausedLines([3], [0]), [0]);
});

test("public log: signed reports chain, verify, and tampering shows", () => {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" });
  const key = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x!, "base64url"), Buffer.from(jwk.y!, "base64url")]).toString("base64url");
  const log: LogEntry[] = [];
  for (let n = 0; n < 3; n++) {
    const body = JSON.stringify({ impressions: [{ petKey: "pet.a", campaignId: "7", hook: n % 2 }] });
    const time = String(1_700_000_000_000 + n);
    const sig = sign("sha256", Buffer.from(canonical("POST", "/impressions", time, body)), { key: privateKey, dsaEncoding: "der" }).toString("base64url");
    appendEntry(log, { campaign: "7", hour: 472222, counts: n % 2 ? [0, 1] : [1, 0], pet: anonPet("pet.a"), key, time, sig, body });
  }
  const check = (e: LogEntry) => verify("sha256", Buffer.from(canonical("POST", "/impressions", e.time!, e.body)), { key: createPublicKey({ key: { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y }, format: "jwk" }), dsaEncoding: "der" }, Buffer.from(e.sig!, "base64url"));
  assert.deepEqual(verifyLog(log, check), { ok: true, total: 3, problems: [] });
  const forged = structuredClone(log);
  forged[1].counts = [0, 5];
  assert.match(verifyLog(forged, check).problems.join(), /entry 1: hash/);
  const dropped = [log[0], log[2]];
  assert.ok(verifyLog(dropped, check).problems.some((p) => /chain|index/.test(p)), "a removed entry breaks the chain");
  assert.notEqual(anonPet("pet.a"), "pet.a");
});

test("park keeps exactly five fields, shuffles, and forgets pets that left", () => {
  const p = parkPet({ id: "a".repeat(24), name: "Mochi", species: "gremlo", stage: "buddy", outfit: ["beanie", "rolex"], owner: "x", earnings: 5 });
  assert.deepEqual(Object.keys(p).sort(), ["id", "name", "outfit", "species", "stage"]);
  assert.deepEqual(p.outfit, ["beanie"]);
  assert.throws(() => parkPet({ id: "nope", name: "x", species: "gremlo", stage: "buddy" }));
  const park: Park = { a: { pet: p, seen: 0 }, b: { pet: { ...p, id: "b".repeat(24) }, seen: 1_000_000 } };
  assert.deepEqual(parkList(park, 1_000_001).map((x) => x.id), ["b".repeat(24)]);
});

test("team relay: opt-in on both sides, 3 an hour, 30 minutes to deliver, nothing extra kept", () => {
  const r: Relay = { members: {}, visits: [] };
  const t0 = 1_000_000;
  const visit = { team: "acme-team", from: "ana", to: "bo", species: "gremlo-pip", pr: 482, url: "https://github.com/acme/app/pull/482", secret: "x" };
  assert.throws(() => relaySend(r, visit, t0), /join/);
  relayJoin(r, { team: "acme-team", handle: "ana" }, t0);
  relayJoin(r, { team: "acme-team", handle: "bo" }, t0);
  for (let i = 0; i < 3; i++) relaySend(r, visit, t0 + i);
  assert.throws(() => relaySend(r, visit, t0 + 10), /3 visits/);
  const inbox = relayInbox(r, new URLSearchParams({ team: "acme-team", handle: "bo" }), t0 + 60_000);
  assert.equal(inbox.length, 3);
  assert.deepEqual(Object.keys(inbox[0]).sort(), ["at", "from", "pr", "species", "url"]);
  assert.equal(relayInbox(r, new URLSearchParams({ team: "acme-team", handle: "bo" }), t0 + 61_000).length, 0, "delivered once");
  relaySend(r, { ...visit }, t0 + 3_600_001);
  assert.equal(relayInbox(r, new URLSearchParams({ team: "acme-team", handle: "bo" }), t0 + 3_600_001 + 31 * 60_000).length, 0, "expired after 30 min");
});

test("gallery: PNG size check and three reports pause a species", () => {
  const png = Buffer.alloc(33);
  png.writeUInt32BE(0x89504e47, 0); png.write("IHDR", 12, "ascii"); png.writeUInt32BE(1536, 16); png.writeUInt32BE(39 * 208, 20);
  assert.deepEqual(pngSize(png), { w: 1536, h: 8112 });
  const rows = Object.fromEntries([...Array(39)].map((_, i) => [`r${i}`, { row: i, frames: 8 }]));
  const json = Buffer.from(JSON.stringify({ gremlo: { rows, cell: [192, 208], columns: 8 } })).toString("base64");
  assert.deepEqual(checkSubmission({ "pet.json": json, "spritesheet.png": png.toString("base64") }), { rows: 39 });
  assert.throws(() => checkSubmission({ "pet.json": json, "spritesheet.png": png.toString("base64"), "run.sh": "eA==" }), /unexpected/);
  const s: Submission = { id: "1", name: "x", creator: "c", status: "listed", reports: 0, at: 0, rows: 39 };
  report(s); report(s);
  assert.equal(s.status, "listed");
  assert.equal(report(s).status, "paused");
});

import { addAnswer, getState, putState, takeAnswers, type Mailbox } from "./phone.ts";
test("phone relay: sealed boxes only, answers drained once, bad input refused", () => {
  const m: Record<string, Mailbox> = {}, ch = "ab".repeat(16);
  assert.throws(() => putState(m, "nope", { box: "eA==" }, 0), /channel/);
  assert.throws(() => addAnswer(m, ch, { box: "eA==" }, 0), /no Mac/);
  putState(m, ch, { box: "c2VhbGVk" }, 1);
  assert.deepEqual(getState(m, ch), { box: "c2VhbGVk" });
  assert.throws(() => addAnswer(m, ch, { box: "not base64!" }, 2), /base64/);
  addAnswer(m, ch, { box: "YQ==" }, 2);
  assert.deepEqual(takeAnswers(m, ch, 3), { boxes: ["YQ=="] });
  assert.deepEqual(takeAnswers(m, ch, 4), { boxes: [] });
});

import { nextEntry } from "./trust.ts";
test("public log: entries written one at a time chain exactly like an in-memory log", () => {
  const e = (n: number) => ({ campaign: "1", hour: 1, counts: [n, 0, 0, 0, 0], pet: "p", key: null, time: null, sig: null, body: `{"n":${n}}` });
  const mem: LogEntry[] = [];
  [1, 2, 3].forEach((n) => appendEntry(mem, e(n)));
  let head: { i: number; hash: string } | null = null;
  const file: LogEntry[] = [];
  for (const n of [1, 2, 3]) { const x = nextEntry(head, e(n)); file.push(x); head = { i: x.i, hash: x.hash }; }
  assert.deepEqual(file, mem);
});
