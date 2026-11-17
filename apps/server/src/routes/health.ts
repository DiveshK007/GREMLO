// Liveness and health. /livez says the process answers; /health says whether the money side needs a person.

import { type IncomingMessage } from "node:http";
import { balanceOf, network, operatorId, vault } from "../chain.ts";
import { health } from "../health.ts";
import { type Loose } from "../json.ts";
import { WORKER_MS, WORKER_ON, worker } from "./settle.ts";
import { NOT_HANDLED, type Url } from "../state.ts";

/** GET /health: 200 when nothing needs a person, 503 with the reasons when something does (for an uptime monitor). */
async function healthCheck() {
  const operatorBalance = await balanceOf(operatorId)
    .then((b) => BigInt(b))
    .catch(() => null);
  const h = health({ workerOn: WORKER_ON, everyMs: WORKER_MS, startedAt: worker.startedAt, lastOk: worker.lastOk, lastError: worker.lastError, operatorBalance, expiredUnpaid: worker.expiredUnpaid });
  return {
    httpStatus: h.ok ? 200 : 503,
    body: {
      ...h,
      worker: { on: WORKER_ON, everyMinutes: WORKER_MS / 60_000, lastOk: worker.lastOk, lastError: worker.lastError },
      operator: { account: operatorId, balance: operatorBalance?.toString() ?? null },
      network,
      vault,
    },
  };
}

/** The health routes, or NOT_HANDLED. */
export async function handle(req: IncomingMessage, { pathname }: Url): Promise<Loose> {
  if (req.method === "GET" && pathname === "/livez") return { ok: true }; // the process answers; touches nothing (the host's liveness probe)
  if (req.method === "GET" && pathname === "/health") return healthCheck();
  return NOT_HANDLED;
}
