"use client";

import { useEffect, useState } from "react";
import { copyText, useNotch } from "@/components/Shell";
import { BriefStep } from "./BriefStep";
import { BudgetStep } from "./BudgetStep";
import { Dashboard } from "./Dashboard";
import { HookStep } from "./HookStep";
import { Receipt } from "./Receipt";
import { Summary } from "./Summary";
import { Tx } from "./shared";
import { useDashboard } from "./useDashboard";
import { useFunding } from "./useFunding";
import "./brand.css";

export default function FundCampaign() {
  const notch = useNotch();
  const [tab, setTab] = useState<"new" | "dash">("new");
  const [account, setAccount] = useState<string | null>(null);
  const [busy, setBusy] = useState("");
  const [copied, setCopied] = useState(false);
  const d = useDashboard({ account, busy, setBusy });
  const f = useFunding({ account, setAccount, busy, setBusy, onPaid: d.setLookupId });
  const { lookupId, setLookupId, loadCampaign } = d;
  const { funded, n, walletError, onConnect, unsavedDraft, retryError, retrySave, retrying, paidTx } = f;

  // a share link like /brand?c=12 opens straight on that campaign's dashboard
  useEffect(() => {
    const c = new URLSearchParams(window.location.search).get("c");
    if (c && /^\d+$/.test(c)) {
      setTab("dash");
      setLookupId(c);
      void loadCampaign(c);
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps -- once on mount: only the first address decides the tab

  useEffect(() => {
    if (busy === "fund") notch.set("wait", "confirm in your wallet");
    else if (busy) notch.set("think");
    else notch.base("rest");
  }, [busy, notch]);

  async function share(id: string) {
    if (!(await copyText(`${window.location.origin}/brand?c=${id}`, "Link copied"))) return;
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  const head = (
    <div className="wrap">
      {tab === "dash" ? (
        <div style={{ height: 36 }} />
      ) : (
        <div className="sec-head">
          <div>
            <div className="eyebrow">For brands</div>
            <h1 className="dsp">
              Put your hook
              <br />
              on the sign.
            </h1>
          </div>
          <p>Your hook, carried across a developer’s screen by a tiny pet while their AI agent works. Pay per real, verified view.</p>
        </div>
      )}
      <nav className="tabs" aria-label="Brand console">
        <a
          href="/brand"
          aria-current={tab === "new" ? "page" : undefined}
          onClick={(e) => {
            e.preventDefault();
            setTab("new");
            window.history.replaceState(null, "", "/brand");
          }}
        >
          New campaign
        </a>
        <a
          href={lookupId ? `/brand?c=${lookupId}` : "/brand"}
          aria-current={tab === "dash" ? "page" : undefined}
          onClick={(e) => {
            e.preventDefault();
            setTab("dash");
          }}
        >
          Campaign dashboard
        </a>
      </nav>
    </div>
  );

  // ---------- receipt ----------
  if (funded) {
    return (
      <div className="wrap narrow" style={{ maxWidth: 1040 }}>
        <Receipt
          funded={funded}
          retrying={f.retrying}
          retryError={f.retryError}
          retrySave={f.retrySave}
          share={share}
          copied={copied}
          onView={(id) => {
            f.setFunded(null);
            setTab("dash");
            void loadCampaign(id);
          }}
          onAnother={() => {
            f.startAnother();
            setTab("new");
            window.history.replaceState(null, "", "/brand");
          }}
        />
      </div>
    );
  }

  // ---------- dashboard ----------
  if (tab === "dash") {
    return (
      <>
        {head}
        <div className="wrap">
          <Dashboard d={d} busy={busy} copied={copied} share={share} />
        </div>
      </>
    );
  }

  // ---------- new campaign ----------
  return (
    <>
      {head}
      <div className="wrap">
        <div className="panel wallet">
          {account ? (
            <>
              <span className="pill">
                <i />
                Connected
              </span>
              <span>
                Paying from <span className="acct">{account}</span>
              </span>
            </>
          ) : (
            <>
              <button type="button" className="btn ghost sm" onClick={onConnect}>
                Connect wallet
              </button>
              <p>You pay from your own wallet. Nothing moves until you confirm there.</p>
            </>
          )}
        </div>
        {walletError && (
          <div className="bad" role="alert">
            {walletError}
          </div>
        )}
        {unsavedDraft && (
          <div className="bad" role="alert" style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center" }}>
            <span>
              Campaign #{unsavedDraft.campaignId} is paid, but its hooks weren’t saved on the server. They’re kept on this device.{retryError && <> Retry failed: {retryError}</>}
            </span>
            <button type="button" className="btn solid sm" onClick={retrySave} disabled={retrying} aria-busy={retrying}>
              {retrying ? "Saving…" : "Retry saving"}
            </button>
          </div>
        )}
        {paidTx && (
          <p className="note">
            Receipt: <Tx hash={paidTx} full />
          </p>
        )}

        <div className="build">
          <div>
            <BriefStep f={f} />
            {(f.hooks.length > 0 || f.dropped.length > 0 || (f.hooksError && f.hooksError.startsWith("Couldn't"))) && busy !== "hooks" && <HookStep f={f} />}
            <BudgetStep f={f} />
          </div>
          <Summary f={f} />
        </div>
        {f.hooks.length > 0 && (
          <div className="mobibar">
            <span>{n ? `${n} line${n === 1 ? "" : "s"} · ~${f.estimate} views · ${f.budget} NEAR` : "Pick a hook to fund"}</span>
            <a className="btn solid sm" href="#s3">
              Review &amp; fund
            </a>
          </div>
        )}
      </div>
    </>
  );
}
