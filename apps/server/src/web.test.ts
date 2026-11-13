import { test } from "node:test";
import assert from "node:assert/strict";
import { keccak256, toBytes } from "viem";
import { checkLine, checkUrl, clickTarget, cors, WEB_ORIGIN, worldSign } from "./web.ts";

test("world sign returns the four RP fields, never the key, and rejects unknown actions", () => {
  const key = "11".repeat(32); // throwaway test key
  const s = worldSign("register-pet", key);
  assert.deepEqual(Object.keys(s), ["sig", "nonce", "created_at", "expires_at"]);
  assert.ok(s.sig && s.nonce && s.expires_at > s.created_at);
  assert.ok(!JSON.stringify(s).includes(key));
  assert.throws(() => worldSign("pay-me", key), (e: any) => e.status === 400);
  assert.throws(() => worldSign(null, key), (e: any) => e.status === 400);
});

const line = "Ship faster with Acme CI";
const hash = keccak256(toBytes(line));
const status = (fn: () => unknown, code: number) => assert.throws(fn, (e: any) => e.status === code);

test("line text is accepted only when it hashes to the onchain lineHash", () => {
  assert.equal(checkLine(line, hash, hash.toUpperCase().replace("0X", "0x")), hash.toLowerCase());
  status(() => checkLine("Ship faster with Acme CD", hash, hash), 400); // text does not match its hash
  status(() => checkLine(line, hash, keccak256(toBytes("other"))), 409); // campaign holds a different line
  status(() => checkLine("", hash, hash), 400);
  status(() => checkLine(line, "0x12", hash), 400);
});

test("a picked hook set is 1-5 hooks of at most 80 characters, hashed as one line", () => {
  const set = ["Logs, found.", "Still grepping at 2am?", "First 1M logs free"].join("\n");
  const h = keccak256(toBytes(set));
  assert.equal(checkLine(set, h, h), h.toLowerCase());
  const six = Array(6).fill("hook").join("\n");
  status(() => checkLine(six, keccak256(toBytes(six)), keccak256(toBytes(six))), 400);
  const long = "x".repeat(81);
  status(() => checkLine(long, keccak256(toBytes(long)), keccak256(toBytes(long))), 400);
  const blank = "one\n\nthree";
  status(() => checkLine(blank, keccak256(toBytes(blank)), keccak256(toBytes(blank))), 400);
});

test("brand URLs must be public https; clicks get UTM tags", () => {
  assert.equal(checkUrl("https://acme.dev/pricing"), "https://acme.dev/pricing");
  for (const bad of ["http://acme.dev", "https://localhost:3000", "https://user:pw@acme.dev", "javascript:alert(1)", "https://intranet", 42]) {
    status(() => checkUrl(bad), 400);
  }
  const t = new URL(clickTarget("https://acme.dev/pricing?ref=x", "7", 2));
  assert.equal(t.origin + t.pathname, "https://acme.dev/pricing");
  assert.equal(t.searchParams.get("ref"), "x");
  assert.equal(t.searchParams.get("utm_source"), "gremlo");
  assert.equal(t.searchParams.get("utm_campaign"), "7");
  assert.equal(t.searchParams.get("utm_content"), "hook2");
});

test("CORS allows the web app and answers preflight", () => {
  const headers: Record<string, unknown> = {};
  let code = 0;
  const res: any = { setHeader: (k: string, v: unknown) => (headers[k] = v), writeHead: (c: number, h: object) => { code = c; Object.assign(headers, h); }, end() {} };
  assert.equal(cors({ method: "GET" } as any, res), false);
  assert.equal(headers["Access-Control-Allow-Origin"], WEB_ORIGIN);
  assert.equal(cors({ method: "OPTIONS" } as any, res), true);
  assert.equal(code, 204);
  assert.match(String(headers["Access-Control-Allow-Headers"]), /content-type/);
});
