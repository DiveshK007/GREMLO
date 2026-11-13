"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { activeCampaign, publicStats, tryHook, type ActiveCampaign, type Hook, type PublicStats } from "@/lib/api";
import { formatNear, NETWORK, VAULT_ID } from "@/lib/config";
import { Plate } from "@/components/Plate";
import { useAccent, useNotch } from "@/components/Shell";
import { useRotate } from "@/components/useRotate";
import "./live.css";

// The proof page: the line on a sign this minute, the running totals, and one real AI call. Product copy names no
// chain; the network, contract and inference provider appear only in the technical footnote at the bottom.

const EXAMPLES = ["Ship faster with Acme CI", "Tests in three seconds", "Logs you can read"];
const FORMAT: Record<string, string> = { humour: "Humour", sarcasm: "Sarcasm", offer: "Offer", question: "Question", "bold-claim": "Bold claim", urgency: "Urgency", story: "Mini story", "dev-meme": "Dev meme" };
const TRY_PETS = ["pip", "byte", "gloop"];

export default function Live() {
  useAccent("tako");
  const notch = useNotch();
  const [campaign, setCampaign] = useState<ActiveCampaign | undefined>(undefined);
  const [s, setS] = useState<PublicStats | null | undefined>(undefined);
  const [statsError, setStatsError] = useState("");
  const [product, setProduct] = useState("");
  const [busy, setBusy] = useState(false);
  const [hooks, setHooks] = useState<Hook[]>([]);
  const [requestId, setRequestId] = useState("");
  const [tryError, setTryError] = useState("");

  useEffect(() => {
    notch.set("think");
    Promise.allSettled([
      activeCampaign().then((c) => setCampaign(c)).catch(() => setCampaign(null)),
      publicStats().then(setS).catch((e) => { setS(null); setStatsError((e as Error).message); }),
    ]).then(() => notch.base("rest"));
  }, [notch]);

  const live = campaign?.hooks?.length ? campaign.hooks : null;
  const line = useRotate(live ?? EXAMPLES);

  async function go(e: React.FormEvent) {
    e.preventDefault();
    setTryError("");
    if (product.trim().length < 3) return setTryError("Say what your product is first.");
    setBusy(true);
    notch.set("think");
    try {
      const r = await tryHook(product.trim(), "developers");
      setHooks(r.hooks);
      setRequestId(r.requestId);
      notch.set("done", `${r.hooks.length} lines written`);
    } catch (err) {
      setTryError((err as Error).message);
      notch.base("rest");
    } finally {
      setBusy(false);
    }
  }

  const tot = (label: string, value: string | null) => (
    <div><span className="lbl">{label}</span><span className={`big${value == null ? " dash" : ""}`}>{value ?? (s === undefined ? "…" : "—")}</span></div>
  );

  return (
    <div className="wrap">
      <div className="sec-head">
        <div><div className="eyebrow">Live numbers</div><h1 className="dsp">The real numbers, right now.</h1></div>
        <p>For judges and the curious: the line on a sign this minute, the running totals, and one real AI call you can make yourself. The story lives on the <Link href="/">home page</Link>.</p>
      </div>

      <div className="stage now">
        {line && campaign !== undefined && <span style={{ marginBottom: 18 }}><Plate species="tako" line={line} brand={live ? campaign!.brand : "Example"} scale={0.7} k={5} /></span>}
        <div className="tl">
          {campaign === undefined ? <span className="faint" style={{ fontSize: 13 }}>Reading the live line…</span>
            : live ? <><span className="pill live"><i />Live now</span><span className="faint" style={{ fontSize: 13 }}>Campaign #{campaign!.campaignId} · rotating its {live.length} line{live.length === 1 ? "" : "s"}</span></>
            : <><span className="ex">Example hooks</span><span className="faint" style={{ fontSize: 13 }}>No campaign is running. These are examples.</span></>}
        </div>
      </div>

      <div className="sub-head">
        <div><div className="eyebrow">Totals</div><h2>So far</h2></div>
        <span className="n" role="status">{s === undefined ? "reading…" : s ? "they only grow with real use" : ""}</span>
      </div>
      {s === null && <div className="bad" role="alert" style={{ marginBottom: 14 }}>Can’t read the totals right now. <span className="mono faint" style={{ fontSize: 12.5 }}>{statsError}</span></div>}
      {s?.seeded && <div className="seeded" style={{ marginBottom: 14 }}><b>Seeded data</b>not real money. A local sandbox, filled for testing.</div>}
      <div className="totals">
        {tot("Campaigns funded", s ? String(s.campaigns) : null)}
        {tot("Views settled", s ? s.settledViews : null)}
        {tot("Paid to developers", s ? Number(formatNear(BigInt(s.paidWei))).toFixed(4) : null)}
        {tot("Verified pets", s ? String(s.pets) : null)}
      </div>
      <p className="faint" style={{ fontSize: 13, margin: "12px 0 0" }}>Read from the campaign contract’s own totals.</p>

      <div className="sub-head"><div><div className="eyebrow">Try it</div><h2>Type your product. Watch the pet pitch it.</h2></div><span className="n">one real AI call · rate limited</span></div>
      <div className="try">
        <form onSubmit={go}>
          <div className="field" data-invalid={tryError.startsWith("Say what") || undefined}>
            <label htmlFor="prod">Your product</label>
            <input id="prod" className="big" value={product} onChange={(e) => setProduct(e.target.value)} maxLength={160} placeholder="Clearlog, log search for TS teams" aria-invalid={tryError.startsWith("Say what") || undefined} />
          </div>
          <button type="submit" className="btn solid" disabled={busy} aria-busy={busy}>{busy ? <><span className="spin" />Writing…</> : "Write hooks"}</button>
          {busy && <p className="note" role="status"><span className="spin" aria-hidden="true" />Writing with private inference… Real inference, usually 20 to 60 seconds.</p>}
          {tryError && <div className="bad" role="alert">{tryError}</div>}
        </form>
        <div>
          {hooks.length > 0 ? (
            <>
              <div className="stage signs">{hooks.slice(0, 3).map((h, i) => <Plate key={h.text} species={TRY_PETS[i]} line={h.text} brand="Example" scale={0.5} k={3.5} />)}</div>
              <p className="mono faint" style={{ fontSize: 12, margin: "10px 0 0" }}>Example only · written by AI · request <span style={{ color: "var(--fg)", wordBreak: "break-all" }}>{requestId}</span></p>
              <ul className="fl">{hooks.map((h) => <li key={h.text}><span>{FORMAT[h.format] ?? h.format}</span>{h.text}</li>)}</ul>
            </>
          ) : (
            <div className="stage signs" style={{ alignItems: "center", justifyContent: "center" }}>
              <p className="mono faint" style={{ fontSize: 12, textAlign: "center", maxWidth: "34ch" }}>Three lines appear here on three pets’ signs, each labelled example.</p>
            </div>
          )}
        </div>
      </div>

      <div className="sub-head"><div><div className="eyebrow">Proof · technical</div><h2 style={{ fontSize: 18 }}>What this page reads</h2></div></div>
      <p className="tech">
        Network: <b>NEAR {NETWORK}</b> · contract <b>{VAULT_ID || "—"}</b> · inference: <b>NEAR AI Cloud</b> (private inference), every call returns a request ID · live line: <b>GET /campaigns/active</b> · totals: <b>GET /stats</b>
      </p>
    </div>
  );
}
