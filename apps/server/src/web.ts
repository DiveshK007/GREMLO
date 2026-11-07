import type { IncomingMessage, ServerResponse } from "node:http";
import { keccak256, toBytes } from "viem";
import { signRequest } from "@worldcoin/idkit-core/signing";
import { bad, HttpError, WORLD_ACTIONS } from "./register.ts";

/** RP signature for an IDKit request. The signing key stays on the server; only the signature leaves. */
export function worldSign(action: string | null, signingKeyHex: string) {
  if (!action || !WORLD_ACTIONS.has(action)) throw bad("unknown action");
  const s = signRequest({ action, signingKeyHex });
  return { sig: s.sig, nonce: s.nonce, created_at: s.createdAt, expires_at: s.expiresAt };
}

export const WEB_ORIGIN = process.env.WEB_ORIGIN ?? "http://localhost:3000"; // the deployed web app in production

/** CORS for apps/web. Returns true when it fully answered a preflight. */
export function cors(req: IncomingMessage, res: ServerResponse) {
  res.setHeader("Access-Control-Allow-Origin", WEB_ORIGIN);
  res.setHeader("Vary", "Origin");
  if (req.method !== "OPTIONS") return false;
  res.writeHead(204, {
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Max-Age": "600",
  });
  res.end();
  return true;
}

/**
 * The chain stores only keccak256(line). A line is the brand's picked hooks joined by newlines (1-5 hooks,
 * each 1-80 chars; v1 campaigns are a set of one). Text is saved only if it hashes to what the campaign holds.
 */
export function checkLine(line: unknown, lineHash: unknown, onchainHash: string) {
  if (typeof line !== "string" || !line.trim()) throw bad("line is required");
  const hooks = line.split("\n");
  if (hooks.length > 5 || hooks.some((h) => !h.trim() || h.length > 80)) throw bad("line must be 1-5 hooks of 1-80 characters, one per line");
  if (typeof lineHash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(lineHash)) throw bad("lineHash must be a 32-byte hex");
  const h = keccak256(toBytes(line)).toLowerCase();
  if (h !== lineHash.toLowerCase()) throw bad("keccak256(line) does not match lineHash");
  if (h !== onchainHash.toLowerCase()) throw new HttpError(409, "lineHash does not match the onchain campaign");
  return h;
}

/** Brand landing page: https only, no credentials, no localhost. Returned normalised. */
export function checkUrl(u: unknown) {
  if (typeof u !== "string" || u.length > 300) throw bad("url must be an https link up to 300 characters");
  let url: URL;
  try { url = new URL(u); } catch { throw bad("url is not a valid link"); }
  if (url.protocol !== "https:" || url.username || url.password || /^(localhost|127\.|0\.|\[::1\])/.test(url.hostname) || !url.hostname.includes(".")) {
    throw bad("url must be a public https link");
  }
  return url.toString();
}

/** Where a sign click goes: the brand's URL with UTM tags so they can see Notchi traffic. */
export function clickTarget(url: string, campaignId: string, hook: number) {
  const u = new URL(url);
  u.searchParams.set("utm_source", "notchi");
  u.searchParams.set("utm_medium", "pet");
  u.searchParams.set("utm_campaign", campaignId);
  u.searchParams.set("utm_content", `hook${hook}`);
  return u.toString();
}
