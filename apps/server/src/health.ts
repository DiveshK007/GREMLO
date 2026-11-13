// Whether the money side needs a person: the settlement worker stalled or failing, the operator too low on NEAR to
// pay gas for settlements and charges, or views that expired unpaid. GET /health answers 503 with the reasons, so
// any uptime monitor can page on it. Pure; index.ts feeds it.

export const OPERATOR_LOW = 5n * 10n ** 23n; // 0.5 NEAR: below this, settlements and charges start failing for gas

export type HealthInput = {
  workerOn: boolean;
  everyMs: number;          // how often the worker runs
  startedAt: number;        // when this server started
  lastOk: number | null;    // when a worker pass last finished without a top-level error
  lastError: string | null; // the most recent worker error
  operatorBalance: bigint | null; // null: couldn't be read
  expiredUnpaid: number;    // views that expired unpaid since start
};

export function health(h: HealthInput, now = Date.now()) {
  const reasons: string[] = [];
  // three missed passes in a row means the worker is stuck or failing, not just slow (a fresh start gets the same grace)
  if (h.workerOn && now - (h.lastOk ?? h.startedAt) > 3 * h.everyMs) reasons.push(`settlement worker: no good pass in ${Math.round((now - (h.lastOk ?? h.startedAt)) / 60_000)} min${h.lastError ? ` (last error: ${h.lastError})` : ""}`);
  if (h.operatorBalance === null) reasons.push("operator balance: can't be read");
  else if (h.operatorBalance < OPERATOR_LOW) reasons.push("operator balance: under 0.5 NEAR, settlements and charges will fail for gas");
  if (h.expiredUnpaid > 0) reasons.push(`${h.expiredUnpaid} view${h.expiredUnpaid === 1 ? "" : "s"} expired unpaid since start`);
  return { ok: reasons.length === 0, reasons };
}
