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

export const WEB_ORIGIN = "http://localhost:3000";

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

/** The chain stores only keccak256(line). Text is saved only if it hashes to what the campaign holds. */
export function checkLine(line: unknown, lineHash: unknown, onchainHash: string) {
  if (typeof line !== "string" || !line.trim() || line.length > 120) throw bad("line must be 1..120 characters");
  if (typeof lineHash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(lineHash)) throw bad("lineHash must be a 32-byte hex");
  const h = keccak256(toBytes(line)).toLowerCase();
  if (h !== lineHash.toLowerCase()) throw bad("keccak256(line) does not match lineHash");
  if (h !== onchainHash.toLowerCase()) throw new HttpError(409, "lineHash does not match the onchain campaign");
  return h;
}
