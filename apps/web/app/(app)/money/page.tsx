"use client";

import { useEffect, useRef, useState } from "react";
import { activeCampaign, publicStats, type PublicStats } from "@/lib/api";
import { formatNear, SERVER_URL } from "@/lib/config";
import { Plate } from "@/components/Plate";
import { useAccent, useNotch } from "@/components/Shell";
import "./money.css";

// R2 §16: where a brand's money goes, with live totals read from the campaign contract. A dash means unknown.
// The copy says only what runs: no weekly payout job and no repeat-brand rule exist yet, so neither is claimed.

const STEPS: [string, string][] = [
  ["Brand pays", "A brand pays per 1,000 sightings, up front, into the campaign."],
  ["Platform fee", "The platform fee is — until the rate is published. Never a made-up rate."],
  ["Pet’s balance", "The rest goes to the pet’s balance, one settlement per pet, each with a receipt."],
  ["Meals first", "Part of each settlement feeds the pet’s own compute budget, which pays for its thinking."],
  ["Owner", "Surplus above a small reserve goes to the owner’s payout account."],
  ["Refund", "Unspent budget goes back to the brand when the campaign closes."],
];
const EXAMPLES: [string, string][] = [["gremlo", "Ship faster with Acme CI"], ["pip", "Tests in three seconds"], ["byte", "Logs you can read"], ["tako", "Ship it"], ["moss", "Deploys on push"], ["puff", "Fewer flaky tests"], ["wisp", "Docs that keep up"], ["gloop", "Errors, explained"]];

/** Counts up to a real number once (reduced motion shows it at once). */
function Count({ value }: { value: string }) {
  const [shown, setShown] = useState(value);
  useEffect(() => {
    const n = parseFloat(value), dec = (value.split(".")[1] ?? "").length;
    if (!isFinite(n) || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return setShown(value);
    const t0 = performance.now();
    let raf = 0;
    const tick = (now: number) => {
      const k = Math.min(1, (now - t0) / 1200);
      setShown((n * (1 - (1 - k) ** 3)).toFixed(dec));
      if (k < 1) raf = requestAnimationFrame(tick); else setShown(value);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value]);
  return <>{shown}</>;
}

function Parade() {
  const row = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let x = 0, last = performance.now(), raf = 0;
    const go = (now: number) => {
      const el = row.current;
      if (!el) return;
      x -= (now - last) * 0.03;
      last = now;
      if (-x > el.scrollWidth / 2) x = 0;
      el.style.transform = `translateX(${x}px)`;
      raf = requestAnimationFrame(go);
    };
    raf = requestAnimationFrame(go);
    return () => cancelAnimationFrame(raf);
  }, []);
  return (
    <div className="parade" aria-hidden="true">
      <div className="row" ref={row}>{[...EXAMPLES, ...EXAMPLES].map(([id, t], i) => <Plate key={i} species={id} line={t} brand="Example" scale={0.5} k={3.5} />)}</div>
      <span className="ex">example lines</span>
    </div>
  );
}

export default function Money() {
  useAccent("pip");
  const notch = useNotch();
  const [s, setS] = useState<PublicStats | null>(null);
  const [error, setError] = useState("");
  const [live, setLive] = useState<string | null>(null); // a real running campaign, for the public log link

  useEffect(() => {
    notch.set("think");
    // publicStats throws on a non-2xx, so the server's own message shows instead of dashes
    publicStats().then(setS).catch((e) => setError((e as Error).message)).finally(() => notch.base("rest"));
    activeCampaign().then((c) => setLive(c?.campaignId ?? null)).catch(() => setLive(null));
  }, [notch]);

  const near = (v?: string) => (v ? formatNear(BigInt(v)) : null);
  const tot = (label: string, value: string | null | undefined, sub?: string) => (
    <div>
      <span className="lbl">{label}</span>
      <span className={`big${value == null ? " dash" : ""}`}>{value == null ? "—" : <Count value={value} />}</span>
      {sub && <small>{sub}</small>}
    </div>
  );

  return (
    <>
      <div className="wrap">
        <div className="sec-head">
          <div><div className="eyebrow">Where the money goes</div><h1 className="dsp">It holds one line. That buys its lunch.</h1></div>
          <p>A brand pays for real sightings of one short line on the pet’s sign. Here is every place that money goes, and the live totals so far.</p>
        </div>
      </div>
      <Parade />
      <div className="wrap">
        <div className="flow c6 steps6">
          {STEPS.map(([t, p], i) => (
            <div key={t}><span className="n">0{i + 1}</span><b>{t}</b><p>{p}</p>{i === 1 && <span className="v dash" style={{ marginTop: "auto" }}>—</span>}</div>
          ))}
        </div>

        <div className="sub-head">
          <div><div className="eyebrow">Live</div><h2>So far</h2></div>
          <span className="n" role="status">{error ? "" : s ? "read from the campaign contract just now" : "reading the totals…"}</span>
        </div>
        {s?.seeded && <div className="seeded" style={{ marginBottom: 14 }}><b>Seeded data</b>not real money. A local sandbox, filled for testing.</div>}
        {error && <div className="bad" role="alert" style={{ marginBottom: 14 }}>Can’t read the totals right now. <span className="mono faint" style={{ fontSize: 12.5 }}>{error}</span></div>}
        <div className="totals">
          {tot("Settled sightings", s?.settledViews, "each one a signed report")}
          {tot("Campaigns", s ? String(s.campaigns) : null)}
          {tot("Pets", s ? String(s.pets) : null, "one human each")}
          {tot("Paid to pets", near(s?.paidWei))}
          {tot("Paid for thinking", near(s?.computeChargedWei))}
        </div>

        <div className="sub-head"><div><div className="eyebrow">The rule</div><h2>A sighting counts only when</h2></div></div>
        <div className="rule">
          <ul className="checks">
            <li>the sign has been on screen for 5 seconds or more</li>
            <li>the screen is unlocked, not shared and not recorded</li>
            <li>someone used the Mac in the last 5 minutes</li>
            <li>the pet is under 12 lines an hour</li>
          </ul>
          <div>
            <p style={{ margin: "0 0 14px", color: "var(--fg)" }}>Every counted sighting is a signed report in the campaign’s public log. Check it against the bill yourself:</p>
            <div className="term"><span className="c">$</span> <b>gremlo verify &lt;campaign&gt;</b><br /><span className="c">replays every signed report and totals the bill</span></div>
            {live && <p style={{ margin: "16px 0 0" }}><a className="hash" href={`${SERVER_URL}/campaigns/${live}/log`} target="_blank" rel="noreferrer">Campaign #{live} · public log</a></p>}
          </div>
        </div>
      </div>
    </>
  );
}
