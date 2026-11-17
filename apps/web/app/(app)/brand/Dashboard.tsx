"use client";

import { Pet } from "@/components/Pet";
import { formatNear, formatWhen, SERVER_URL } from "@/lib/config";
import { DashPreview, PREVIEW, Tx } from "./shared";
import type { Dashboard as DashboardState } from "./useDashboard";

/** The campaign dashboard: look up an id, then budget, settlement, per-line numbers and proof. */
export function Dashboard({ d, busy, copied, share }: { d: DashboardState; busy: string; copied: boolean; share: (id: string) => void }) {
  const { lookupId, setLookupId, lookup, stats, arkiv, campaignError, refund, topUp, setTopUp, toppedUp, settlement, loadCampaign, onSettle, onClose, onTopUp } = d;
  const look = (
    <form
      className="lookup"
      onSubmit={(e) => {
        e.preventDefault();
        void loadCampaign(lookupId);
      }}
    >
      <div className="field">
        <label htmlFor="cid">Campaign ID</label>
        <input id="cid" value={lookupId} onChange={(e) => setLookupId(e.target.value.trim())} inputMode="numeric" placeholder="like 2" />
      </div>
      <button type="submit" className="btn ghost" disabled={busy === "lookup"}>
        {busy === "lookup" ? (
          <>
            <span className="spin" />
            Checking…
          </>
        ) : (
          "Check"
        )}
      </button>
      <button type="button" className="btn ghost" onClick={onSettle} disabled={!lookup || busy === "settle"}>
        {busy === "settle" ? (
          <>
            <span className="spin" />
            Settling…
          </>
        ) : (
          "Settle views"
        )}
      </button>
    </form>
  );
  if (!lookup) {
    return (
      <>
        {look}
        {campaignError ? (
          <div className="bad" role="alert" style={{ marginTop: 22 }}>
            {campaignError}
          </div>
        ) : (
          <div className="panel" style={{ marginTop: 28, textAlign: "center", padding: "48px 24px" }}>
            <Pet species={PREVIEW} row="gaze" fps={3} scale={0.5} style={{ margin: "0 auto" }} />
            <p className="muted" style={{ margin: "12px auto 0" }}>
              Enter the number you got after funding, shown as Campaign #N. A share link <span className="mono">/brand?c=3</span> opens straight here.
            </p>
          </div>
        )}
      </>
    );
  }
  const l = lookup;
  const now = BigInt(Math.floor(Date.now() / 1000));
  const st = l.closed ? "closed" : l.endTime > now ? "running" : l.endTime + 3600n > now ? "window" : "past";
  const pct = l.budget > 0n ? Number((l.spent * 100n) / l.budget) : 0; // integer math on yocto
  const status = {
    running: `Running until ${formatWhen(Number(l.endTime) * 1000)}.`,
    window: `Ended. Views can be settled until ${formatWhen(Number(l.endTime + 3600n) * 1000)}; then it can be closed and refunded.`,
    past: "Ended and the settlement window has passed. Close it to refund what’s left.",
    closed: "Closed. Unspent budget was refunded.",
  }[st];
  const pill = {
    running: (
      <span className="pill live">
        <i />
        Running
      </span>
    ),
    window: (
      <span className="pill warn">
        <i />
        Ended · settling
      </span>
    ),
    past: (
      <span className="pill warn">
        <i />
        Ended
      </span>
    ),
    closed: (
      <span className="pill off">
        <i />
        Closed
      </span>
    ),
  }[st];
  const warn = pct >= 100 ? "Budget used up: your hooks have stopped showing." : pct >= 50 ? `${pct}% of the budget is spent.` : "";
  const lines = stats?.lines ?? null;
  const rows = stats ? stats.views.map((v, i) => ({ i, v, c: stats.clicks[i] ?? 0 })).filter((r) => r.v || r.c || lines?.[r.i]) : [];
  const id = lookupId;
  return (
    <>
      {look}
      {campaignError && (
        <div className="bad" role="alert" style={{ marginTop: 22 }}>
          {campaignError}
        </div>
      )}
      <div className="dash-head">
        <div>
          <div className="eyebrow">Brand · {l.brand}</div>
          <h1 className="dsp" style={{ fontSize: "clamp(48px, 7vw, 100px)", margin: "10px 0 0" }}>
            Campaign #{id}
          </h1>
        </div>
        <div className="actions">
          {pill}
          <button type="button" className="btn ghost sm" onClick={() => share(id)}>
            {copied ? "Link copied" : "Copy share link"}
          </button>
        </div>
      </div>
      <div className="two">
        <div>
          <div className="panel">
            <div className="bline">
              <span>
                Budget <b>{formatNear(l.budget)} NEAR</b>
              </span>
              <span>
                spent <b>{formatNear(l.spent)} NEAR</b>
              </span>
              <span>
                left <b>{formatNear(l.remaining)} NEAR</b>
              </span>
            </div>
            <div className={`meter${pct >= 80 ? " hot" : ""}`} role="meter" aria-label="Budget spent" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-valuetext={`${pct}% spent`}>
              <i style={{ width: `${Math.min(100, pct)}%` }} />
            </div>
            {warn && !l.closed && (
              <p style={{ margin: "14px 0 0", color: "var(--fg)", fontWeight: 600 }}>
                {warn}
                {st === "running" && (
                  <span className="muted" style={{ fontWeight: 400 }}>
                    {" "}
                    Top up below to keep them running.
                  </span>
                )}
              </p>
            )}
            {st === "running" && (
              <form className="inline" style={{ marginTop: 18, alignItems: "flex-end", gap: 8, flexWrap: "wrap" }} onSubmit={onTopUp}>
                <div className="field" style={{ margin: 0, flex: "0 1 220px" }}>
                  <label htmlFor="tu">Add budget (NEAR)</label>
                  <input id="tu" value={topUp} onChange={(e) => setTopUp(e.target.value)} inputMode="decimal" style={{ minHeight: 46, padding: "10px 14px" }} />
                </div>
                <button type="submit" className="btn solid" style={{ minHeight: 46 }} disabled={busy === "topup"}>
                  {busy === "topup" ? (
                    <>
                      <span className="spin" />
                      Topping up…
                    </>
                  ) : (
                    "Top up"
                  )}
                </button>
              </form>
            )}
            {toppedUp && (
              <p className="note">
                Added {toppedUp.amount} NEAR: <Tx hash={toppedUp.txHash} />
              </p>
            )}
            {st === "past" && (
              <div className="actions" style={{ marginTop: 18 }}>
                <button type="button" className="btn solid" onClick={onClose} disabled={busy === "close"}>
                  {busy === "close" ? (
                    <>
                      <span className="spin" />
                      Closing…
                    </>
                  ) : (
                    "Close and refund"
                  )}
                </button>
                <span className="note" style={{ margin: 0 }}>
                  Refunds {formatNear(l.remaining)} NEAR to {l.brand}
                </span>
              </div>
            )}
            {refund && (
              <p className="note">
                Refunded {formatNear(refund.amount)} NEAR: <Tx hash={refund.txHash} />
              </p>
            )}
            <p className="note" style={{ marginTop: 16 }}>
              {status}
            </p>
          </div>

          {settlement &&
            (settlement.error ? (
              <div className="panel settle">
                <div className="bad" role="alert" style={{ margin: 0 }}>
                  Settlement stopped: {settlement.error}
                </div>
                <p className="muted" style={{ margin: "8px 0 0", fontSize: 14 }}>
                  Views before the break were paid. The rest stay queued; nothing is charged for them.
                </p>
              </div>
            ) : settlement.count === 0 ? (
              <div className="panel settle" role="status">
                <h3>Settle views</h3>
                <p className="muted" style={{ margin: 0 }}>
                  No views queued for this campaign yet.
                </p>
              </div>
            ) : (
              <div className="panel settle" role="status">
                <h3>
                  Paid {settlement.count} view{settlement.count === 1 ? "" : "s"}, {formatNear(BigInt(settlement.amount))} NEAR
                  {settlement.seeded && (
                    <>
                      {" "}
                      <span className="ex">seeded, local sandbox</span>
                    </>
                  )}
                </h3>
                <ul>
                  {settlement.settled.map((s) => (
                    <li key={s.txHash}>
                      {s.count} to pet <span className="mono">{s.petKey}</span>: <Tx hash={s.txHash} />
                    </li>
                  ))}
                </ul>
              </div>
            ))}

          <div className="sub-head" style={{ paddingTop: 36 }}>
            <h2 style={{ fontSize: 20 }}>How each line is doing</h2>
            <span className="n">Hook # · line · views · clicks · rate</span>
          </div>
          {stats === null ? (
            <div className="panel">
              <div className="bad" role="alert" style={{ margin: 0 }}>
                Can’t read view stats from the server right now.
              </div>
              <p className="muted" style={{ margin: "8px 0 0", fontSize: 14 }}>
                Budget and status above come straight from the campaign contract, so they’re still right.
              </p>
            </div>
          ) : (
            stats && (
              <>
                <table className="tbl">
                  <thead>
                    <tr>
                      <th>Hook</th>
                      <th className="num">Views</th>
                      <th className="num">Clicks</th>
                      <th className="num">Click rate</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.i} className={stats.best === r.i ? "best" : undefined}>
                        <td data-th="Hook" className="wide">
                          <b style={{ color: "var(--fg)" }}>#{r.i + 1}</b> {lines?.[r.i] && <span className="muted">{lines[r.i]}</span>}
                        </td>
                        <td data-th="Views" className="num">
                          {r.v}
                        </td>
                        <td data-th="Clicks" className="num">
                          {r.c}
                        </td>
                        <td data-th="Click rate" className="num">
                          {r.v ? `${((r.c / r.v) * 100).toFixed(1)}%` : "–"}
                        </td>
                      </tr>
                    ))}
                    {rows.length === 0 && (
                      <tr>
                        <td colSpan={4} className="wide">
                          <span className="muted">No views yet. They appear here as developers’ agents start working.</span>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
                <ul className="facts" style={{ marginTop: 16 }}>
                  {stats.best != null && (
                    <li className="good">
                      Best hook so far: #{stats.best + 1}, {((stats.clicks[stats.best] / stats.views[stats.best]) * 100).toFixed(1)}% of views clicked.
                    </li>
                  )}
                  {stats.heldViews > 0 && (
                    <li>
                      {stats.heldViews} view{stats.heldViews === 1 ? "" : "s"} in the fraud check{stats.holdbackHours ? ` (paid after ${stats.holdbackHours}h)` : ""}.
                    </li>
                  )}
                  {Object.entries(stats.voided).map(([reason, k]) => (
                    <li key={reason} className="hot">
                      {k} view{k === 1 ? "" : "s"} voided, not charged: {reason}.
                    </li>
                  ))}
                  {stats.pendingViews > 0 && (
                    <li>
                      {stats.pendingViews} view{stats.pendingViews === 1 ? "" : "s"} waiting to be settled.
                    </li>
                  )}
                  {stats.moments && Object.keys(stats.moments).length > 0 && (
                    <li>
                      By moment:{" "}
                      {Object.entries(stats.moments)
                        .map(([m, k]) => `${m} ${k ?? "(under 50 pets)"}`)
                        .join(" · ")}
                    </li>
                  )}
                  {stats.paused && stats.paused.length > 0 && <li className="hot">Paused by reports: line {stats.paused.map((i) => i + 1).join(", ")}.</li>}
                  {stats.emailAlerts && <li>Budget alerts and the weekly report go to the email you gave.</li>}
                </ul>
              </>
            )
          )}
        </div>
        <div>
          <div className="panel">
            <div className="lbl" style={{ marginBottom: 12 }}>
              Proof
            </div>
            <p style={{ margin: "0 0 14px", fontSize: 14.5, color: "var(--fg)" }}>
              Every counted view is a signed report from a pet.{" "}
              <a href={`${SERVER_URL}/campaigns/${id}/log`} target="_blank" rel="noreferrer">
                Public log
              </a>{" "}
              · check it yourself:
            </p>
            <div className="term">
              <span className="c">$</span> <b>gremlo verify {id}</b>
              <br />
              <span className="c">checks every signed view against the bill</span>
            </div>
            {arkiv?.on && (
              <p className="muted" style={{ margin: "16px 0 0", fontSize: 13.5 }}>
                {arkiv.card ? (
                  <>
                    Mirrored on Arkiv. Campaign card{" "}
                    <span className="mono">
                      {arkiv.card.key.slice(0, 6)}…{arkiv.card.key.slice(-4)}
                    </span>
                    , expires at Arkiv block {arkiv.card.expiresAt}. {arkiv.receipts.length} settlement receipt{arkiv.receipts.length === 1 ? "" : "s"}.{" "}
                    <a href={arkiv.explorer} target="_blank" rel="noreferrer">
                      Arkiv explorer
                    </a>
                  </>
                ) : (
                  "Not on Arkiv yet. It’s published when the campaign is saved."
                )}
              </p>
            )}
          </div>
          {lines && lines.length > 0 && (
            <div className="panel" style={{ marginTop: 16 }}>
              <div className="lbl" style={{ marginBottom: 14 }}>
                Live preview
              </div>
              <DashPreview lines={lines} />
            </div>
          )}
        </div>
      </div>
    </>
  );
}
