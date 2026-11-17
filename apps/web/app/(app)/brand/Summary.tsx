"use client";

import { Plate } from "@/components/Plate";
import { addressLink, VAULT_ID } from "@/lib/config";
import { MAX_PICK, MIN_PICK, PREVIEW } from "./shared";
import type { Funding } from "./useFunding";

export function Summary({ f }: { f: Funding }) {
  const { preview, brief, n, budget, rate, hours, estimate, account, busy, onFund, fundLabel, error } = f;
  return (
    <aside className="summary" aria-label="Campaign summary">
      <div className="panel" style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        <div className="lbl">Preview · what developers see</div>
        <div className="stage">
          {preview ? (
            <span style={{ marginBottom: 14 }}>
              <Plate species={PREVIEW} line={preview} brand={brief.product.split(",")[0].trim() || "your brand"} scale={0.6} k={4} />
            </span>
          ) : (
            <p className="mono faint" style={{ alignSelf: "center", fontSize: 12, textAlign: "center", padding: "0 24px" }}>
              Pick a line and it shows here, on the pet’s sign.
            </p>
          )}
        </div>
        <dl className="kvs">
          <dt>Lines</dt>
          <dd>
            {n} of {MAX_PICK} picked
          </dd>
          <dt>Budget</dt>
          <dd>{n ? `${budget} NEAR` : "—"}</dd>
          <dt>Per view</dt>
          <dd>{n ? `${rate} NEAR` : "—"}</dd>
          <dt>Runs</dt>
          <dd>{n ? `${hours} hours` : "—"}</dd>
        </dl>
        <div className="est">
          <b>{n ? estimate : "–"}</b>
          <span>views, roughly, at this price. Any unspent budget is refunded when the campaign ends.</span>
        </div>
        <button type="button" className="btn solid" onClick={onFund} disabled={!account || !!busy || n < MIN_PICK} aria-busy={!!fundLabel}>
          {fundLabel ? (
            <>
              <span className="spin" />
              {fundLabel}
            </>
          ) : (
            "Fund campaign"
          )}
        </button>
        {fundLabel && (
          <p className="note" role="status" style={{ margin: 0 }}>
            {busy === "fund"
              ? `Your wallet has the request. Approve the deposit of ${budget} NEAR there.`
              : busy === "record"
                ? "Paid. Saving the line text to the server."
                : "The server checks the same rules before any money moves."}
          </p>
        )}
        {!account ? (
          <p className="note" style={{ margin: 0 }}>
            Connect your wallet at the top to fund.
          </p>
        ) : !n && !busy ? (
          <p className="note" style={{ margin: 0 }}>
            Pick at least {MIN_PICK} hook first.
          </p>
        ) : null}
        {error && (
          <div className="bad" role="alert" style={{ margin: 0 }}>
            {error}
          </div>
        )}
        <span className="contract">
          Contract:{" "}
          <a className="hash" href={addressLink(VAULT_ID)} target="_blank" rel="noreferrer">
            {VAULT_ID || "—"}
          </a>
        </span>
      </div>
    </aside>
  );
}
