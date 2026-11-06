import { test } from "node:test";
import assert from "node:assert/strict";
import { keccak256, toBytes } from "viem";
import { checkLine, cors, WEB_ORIGIN, worldSign } from "./web.ts";

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
