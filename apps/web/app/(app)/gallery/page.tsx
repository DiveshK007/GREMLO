"use client";

import { useEffect, useRef, useState } from "react";
import { gallerySheetUrl, gallerySpecies, reportSpecies, type GallerySpecies } from "@/lib/api";
import { Pet } from "@/components/Pet";
import { useAccent, useNotch } from "@/components/Shell";
import "./gallery.css";

// R2 §13: community species, reviewed by two people who play every row. Creators get credit; nothing is sold.
// A paused species stays on the page, marked, so it doesn't vanish for people who already hatched it.

const REASONS = ["Not the creator’s own art", "Offensive or unsafe", "Broken sprite or animation", "Something else"];
const listed = (at: number) => new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "short" }).format(at);

function ReportDialog({ s, onClose }: { s: GallerySpecies; onClose: () => void }) {
  const [reason, setReason] = useState(REASONS[0]);
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const first = useRef<HTMLInputElement>(null);
  useEffect(() => {
    first.current?.focus();
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    addEventListener("keydown", esc);
    return () => removeEventListener("keydown", esc);
  }, [onClose]);
  async function send(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try { await reportSpecies(s.id, reason); setSent(true); } catch (err) { setError((err as Error).message); } finally { setBusy(false); }
  }
  return (
    <div className="dlg" role="dialog" aria-modal="true" aria-labelledby="rt" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      {sent ? (
        <div className="box" role="status">
          <h2 id="rt">Thanks, report sent.</h2>
          <p className="muted" style={{ margin: "6px 0 18px", fontSize: 14 }}>A reviewer looks at it. You won’t see your name anywhere on the card.</p>
          <button type="button" className="btn ghost" onClick={onClose}>Close</button>
        </div>
      ) : (
        <form className="box" onSubmit={send}>
          <h2 id="rt">Report {s.name}</h2>
          <p className="muted" style={{ margin: 0, fontSize: 14 }}>Reports go to the reviewers. Three reports pause new hatches of a species while it’s re-checked. Pets that already hatched keep it.</p>
          <fieldset>
            <legend className="sr">Reason</legend>
            {REASONS.map((r, i) => (
              <label key={r} className="radio"><input ref={i === 0 ? first : undefined} type="radio" name="reason" checked={reason === r} onChange={() => setReason(r)} />{r}</label>
            ))}
          </fieldset>
          {error && <div className="bad" role="alert">{error}</div>}
          <div className="actions">
            <button type="submit" className="btn solid" disabled={busy}>{busy ? <><span className="spin" />Sending…</> : "Send report"}</button>
            <button type="button" className="btn ghost" onClick={onClose}>Cancel</button>
          </div>
        </form>
      )}
    </div>
  );
}

function Card({ s, onReport }: { s: GallerySpecies; onReport: () => void }) {
  return (
    <article className={`card${s.paused ? " paused" : ""}`}>
      <div className="stage">
        <Pet src={gallerySheetUrl(s.id)} row="idle" fps={6} frame={s.paused ? 0 : undefined} scale={0.72} />
        {s.paused && <span className="tr pill warn"><i />Paused · being re-checked</span>}
      </div>
      <div className="body">
        <h3>{s.name}</h3>
        <div className="by">by <b>{s.creator}</b></div>
        <div className="meta">{s.rows} rows · listed {listed(s.at)} · <span>{s.id}</span></div>
        <div className="row">
          {s.paused
            ? <span className="faint" style={{ fontSize: 12.5 }}>New hatches paused after 3 reports.</span>
            : <span className="soon">Installing from the gallery comes in a later Mac release.</span>}
          {!s.paused && <button type="button" className="report" onClick={onReport}>Report</button>}
        </div>
      </div>
    </article>
  );
}

export default function Gallery() {
  useAccent("moss");
  const notch = useNotch();
  const [list, setList] = useState<GallerySpecies[] | null>(null);
  const [error, setError] = useState("");
  const [reporting, setReporting] = useState<GallerySpecies | null>(null);

  async function load() {
    setError("");
    setList(null);
    notch.set("think");
    try { setList([...(await gallerySpecies()).species].sort((a, b) => b.at - a.at)); } catch (e) { setError((e as Error).message); }
    notch.base("rest");
  }
  useEffect(() => { void load(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  let body: React.ReactNode;
  if (error) {
    body = (
      <div className="panel">
        <div className="bad" role="alert" style={{ margin: 0 }}>Can’t reach the gallery right now. <span className="mono faint" style={{ fontSize: 12.5 }}>{error}</span></div>
        <button type="button" className="btn ghost sm" style={{ marginTop: 14 }} onClick={load}>Try again</button>
      </div>
    );
  } else if (!list) {
    body = <div className="cards" role="status" aria-label="Loading species">{[0, 1, 2].map((i) => <div key={i} className="skel" />)}</div>;
  } else if (!list.length) {
    body = (
      <div className="panel empty">
        <Pet species="moss" row="hatch" frames={[0, 1, 0, 2]} fps={3} scale={0.6} />
        <div>
          <h2>None listed yet.</h2>
          <p>The first community species is still in review. Yours could be the first one here.</p>
          <div className="actions" style={{ marginTop: 16 }}><a className="btn ghost sm" href="#make">How to make one</a></div>
        </div>
      </div>
    );
  } else {
    body = (
      <>
        <div className="sub-head" style={{ paddingTop: 0 }}><h2 style={{ fontSize: 20 }}>Listed</h2><span className="n">{list.length} species · newest first</span></div>
        <div className="cards">{list.map((s) => <Card key={s.id} s={s} onReport={() => setReporting(s)} />)}</div>
      </>
    );
  }

  return (
    <>
      <div className="wrap">
        <div className="sec-head">
          <div><div className="eyebrow">Community species</div><h1 className="dsp">Drawn by people, checked twice.</h1></div>
          <p>Pets drawn by the community. Each one passed machine checks and two human reviewers. Only reviewed species can hold a sponsored line.</p>
        </div>
      </div>
      <div className="wrap">
        {body}
        <div id="make">
          <div className="sub-head" style={{ marginTop: 40 }}><div><div className="eyebrow">For artists</div><h2>Make one</h2></div><span className="n">credit, not a storefront</span></div>
          <div className="make">
            <div>
              <p className="muted" style={{ margin: "0 0 16px" }}>Draw a pet on the 8×39 sheet, check it on your own Mac, then send it for review. Nothing in the gallery is sold, and there are no prices. Creators get their name on the card.</p>
              <ol>
                <li><b>new</b> makes a blank sheet and pet.json</li>
                <li><b>validate</b> runs the machine checks</li>
                <li><b>preview</b> walks it across your screen</li>
                <li><b>submit</b> sends it to two human reviewers</li>
              </ol>
              <p className="faint" style={{ fontSize: 13.5, margin: "16px 0 0" }}>Only art you made. Imports from other pet apps stay on your Mac as companions.</p>
            </div>
            <div className="term"><b>gremlo new my-pet</b><br /><b>gremlo validate my-pet</b><br /><b>gremlo preview my-pet</b><br /><b>gremlo submit my-pet --creator &quot;your name&quot;</b></div>
          </div>
        </div>
      </div>
      {reporting && <ReportDialog s={reporting} onClose={() => setReporting(null)} />}
    </>
  );
}
