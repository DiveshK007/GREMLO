"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ApiError, getPet, type PetPublic } from "@/lib/api";
import { addressLink, formatNear, formatWhen, NETWORK, PRODUCT, txLink } from "@/lib/config";
import { knownSpecies, speciesOf, type RowName } from "@/lib/species";
import { Pet } from "@/components/Pet";
import { useAccent, useNotch } from "@/components/Shell";
import "./me.css";

const KEY = "gremlo.pet";
const near = (yocto: string | null | undefined) => (yocto == null ? null : formatNear(BigInt(yocto)));
const STAGES: [string, string, RowName][] = [["Egg", "before hatching", "hatch"], ["Hatchling", "0–9 meals", "idle"], ["Buddy", "10–49 meals", "idle"], ["Elder", "50+ meals", "idle"]];
const MOOD: Record<string, { label: string; pill: string }> = {
  thriving: { label: "Thriving", pill: "live" }, stable: { label: "Stable", pill: "live" }, hungry: { label: "Hungry", pill: "warn" }, asleep: { label: "Asleep", pill: "off" },
};

/** The stage the Mac reported, or one worked out from the meals (receipts) until it has. */
function stageOf(p: PetPublic) {
  const s = (p.stage ?? "").toLowerCase();
  if (["egg", "hatchling", "buddy", "elder"].includes(s)) return s[0].toUpperCase() + s.slice(1);
  const n = p.meals?.length ?? 0;
  return n >= 50 ? "Elder" : n >= 10 ? "Buddy" : "Hatchling";
}

function Tile({ label, value, sub, why }: { label: string; value: string | null; sub?: string; why?: string }) {
  return (
    <div>
      <i>{label}</i>
      {value == null ? <><span className="v dash">—</span>{why && <span className="why">{why}</span>}</> : <><span className="v">{value}</span>{sub && <p>{sub}</p>}</>}
    </div>
  );
}

function Lookup({ name, setName, busy, onShow, primary }: { name: string; setName: (v: string) => void; busy: boolean; onShow: () => void; primary?: boolean }) {
  return (
    <form className="lookup" onSubmit={(e) => { e.preventDefault(); if (name.trim()) onShow(); }}>
      <div className="field">
        <label htmlFor="pn">Pet name</label>
        <input id="pn" value={name} onChange={(e) => setName(e.target.value.toLowerCase())} placeholder="mochi" autoComplete="off" spellCheck={false} />
      </div>
      <button className={`btn ${primary ? "solid" : "ghost"}`} type="submit" disabled={busy || !name.trim()}>{busy ? <><span className="spin" />Loading…</> : "Show"}</button>
    </form>
  );
}

export default function Me() {
  const notch = useNotch();
  const [name, setName] = useState("");
  const [asked, setAsked] = useState("");
  const [pet, setPet] = useState<PetPublic | null>(null);
  const [error, setError] = useState<{ notFound: boolean; message: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const species = pet && knownSpecies(pet.species) ? speciesOf(pet.species) : null;
  useAccent(species?.id ?? "gremlo");
  useEffect(() => { notch.species(species?.id ?? null); return () => notch.species(null); }, [species?.id, notch]);

  async function load(n: string) {
    setError(null);
    setBusy(true);
    setAsked(n);
    notch.set("think");
    try {
      const p = await getPet(n);
      setPet(p);
      try { localStorage.setItem(KEY, n); } catch {}
      window.history.replaceState(null, "", `/me?pet=${encodeURIComponent(n)}`);
      notch.base("rest");
    } catch (e) {
      setPet(null);
      setError({ notFound: e instanceof ApiError && e.status === 404, message: (e as Error).message.split("\n")[0] });
      notch.base("rest");
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    let n = new URLSearchParams(window.location.search).get("pet") ?? "";
    if (!n) try { n = localStorage.getItem(KEY) ?? ""; } catch {}
    if (n) { setName(n); void load(n); }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const lookup = <Lookup name={name} setName={setName} busy={busy} onShow={() => load(name.trim())} primary={!pet} />;

  // first visit: nothing asked yet
  if (!asked) {
    return (
      <div className="wrap">
        <div className="first" style={{ paddingBlock: "clamp(48px, 8vw, 104px) 40px" }}>
          <div>
            <div className="eyebrow">Your pet</div>
            <h1 className="dsp">How is your pet doing?</h1>
            <p className="muted" style={{ fontSize: 17, margin: "0 0 8px" }}>Type its name to see what it earned, how it’s eating and the proof for every thought. Anyone with the link sees the same page.</p>
            {lookup}
          </div>
          <div className="stage" style={{ minHeight: 360, paddingBottom: 40 }}><span className="mini-notch" aria-hidden="true" /><Pet row="peek" fps={2} scale={1} /></div>
        </div>
        <p className="mono faint" style={{ fontSize: 12 }}>No pet yet? <Link href="/pet">Get your pet</Link>.</p>
      </div>
    );
  }

  if (busy && !pet) {
    return (
      <div className="wrap">
        {lookup}
        <div className="me-hero" role="status">
          <div><div className="eyebrow">Your pet</div><h1 className="dsp" style={{ color: "var(--text-3)" }}>{asked}</h1><p className="note">Loading {asked}…</p></div>
          <div className="stage me-stage"><span className="mini-notch" aria-hidden="true" /></div>
        </div>
        <div className="flow c3">{["This week", "Paid by brands, all time", "Level", "Streak", "Views today", "Mood"].map((l) => <div key={l}><i>{l}</i><span className="v dash">—</span></div>)}</div>
      </div>
    );
  }

  if (error || !pet) {
    const nf = error?.notFound;
    return (
      <div className="wrap">
        {lookup}
        <div className="panel empty-box" style={{ marginTop: 40 }}>
          <Pet row={nf ? "gaze" : "fail"} fps={4} scale={0.7} />
          <h2>{nf ? `No pet called “${asked}”.` : `Can’t reach the ${PRODUCT} server.`}</h2>
          <div className="bad" role="alert" style={{ justifyContent: "center" }}>{error?.message ?? "No answer"}</div>
          <p>{nf ? "Check the spelling: names are lowercase, like mochi or mochi-2." : "Nothing here is a guess, so the page stays empty until the server answers."}</p>
          <div className="actions" style={{ justifyContent: "center" }}>
            {nf ? <Link className="btn ghost" href="/pet">Get your pet</Link> : <button className="btn solid" type="button" onClick={() => load(asked)}>Try again</button>}
          </div>
        </div>
      </div>
    );
  }

  const sp = species ?? speciesOf("gremlo");
  const stage = stageOf(pet);
  const meals = pet.meals?.length ?? 0;
  const moodKey = MOOD[pet.mood] ? pet.mood : "stable";
  const mood = MOOD[moodKey];
  const why = pet.moodReason ?? (moodKey === "thriving" ? "ate well and working" : moodKey === "stable" ? "fed and working, nothing to worry about" : "");
  const spName = species ? species.name : "Species not known yet";
  const week = near(pet.week.wei);
  const share = (() => {
    const text = `My ${PRODUCT} pet ${pet.name} earned ${week ?? "—"} this week from ${pet.week.views} verified views while my coding agent worked.${pet.level ? ` Level ${pet.level}` : ""}${pet.streak ? `, ${pet.streak}-day streak` : ""}.`;
    const url = `${window.location.origin}/me?pet=${encodeURIComponent(pet.name)}`;
    return `https://x.com/intent/post?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`;
  })();

  // money shapes the sprite: thriving celebrates, hungry slows and fades, asleep stays in the notch
  const art = moodKey === "asleep" ? (
    <div className="stage me-stage asleep" style={{ justifyContent: "center" }}>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div className="notch" data-state="sleep" style={{ position: "relative" }}>
          <div className="nl nl-sleep" style={{ opacity: 1 }}><span className="eyes"><Pet species={sp.id} row="peek" frame={2} scale={0.19} /></span><span className="zz">z</span><span className="zz">z</span></div>
        </div>
        <p className="mono faint" style={{ fontSize: 12, marginTop: 160, textAlign: "center", padding: "0 20px" }}>Too hungry to leave the notch. It comes out after the next settlement.</p>
      </div>
      <span className="cap ex">{spName}</span>
    </div>
  ) : (
    <div className="stage me-stage">
      <span className="mini-notch" aria-hidden="true" />
      <Pet species={sp.id} row={moodKey === "thriving" ? "celebrate" : "idle"} fps={moodKey === "thriving" ? 8 : moodKey === "hungry" ? 2 : 5}
        scale={moodKey === "hungry" ? 0.82 : 1} style={moodKey === "hungry" ? { opacity: 0.8 } : undefined} />
      <span className="cap ex">{spName}</span>
    </div>
  );

  const c = pet.compute;
  let budget: React.ReactNode;
  if (!c) {
    budget = (
      <div className="panel">
        <div className="bad" role="alert">Can’t read the pet’s budget right now.</div>
        <p className="muted" style={{ margin: "6px 0 0", fontSize: 14 }}>Values show — until it can be read. Nothing below is a guess.</p>
      </div>
    );
  } else {
    const left = BigInt(c.budget), cap = BigInt(c.dailyCap);
    const days = cap > 0n ? Number((left * 1000n) / cap) / 1000 : 0; // integer math on yocto, then one division
    const pct = Math.min(100, Math.round(days * 100));
    const say = left === 0n ? "empty until the next settlement" : days >= 1 ? `${days.toFixed(1)} days of meals at the cap` : `${pct}% of a day at the cap`;
    budget = (
      <div className="panel">
        <div className="budget-top">
          <span className="lbl">{pet.purse ? "Left in the purse, against the daily cap" : "Budget left, against the daily cap"}</span>
          <b>{near(c.budget)}</b>
          <span className="mono faint" style={{ fontSize: 12 }}>{say}</span>
          <div className={`meter${pct < 20 ? " hot" : ""}`} role="meter" aria-label="Budget left against the daily cap" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-valuetext={say}><i style={{ width: `${pct}%` }} /></div>
        </div>
        <div className="flow c3">
          <Tile label="Spent on thinking, all time" value={near(c.spent)} />
          <Tile label="Charged today" value={near(c.chargedToday)} sub={`of ${near(c.dailyCap)} a day`} />
          <Tile label="Rate per call" value={`${near(c.feeSmart)} · ${near(c.feeCheap)}`} sub="smart · cheap" />
        </div>
      </div>
    );
  }

  return (
    <div className="wrap">
      {lookup}
      {pet.seeded && <div className="seeded" style={{ marginTop: 24 }}><b>Seeded</b>Seeded data on a local sandbox, not real money.</div>}
      {pet.paired === false && <p className="note" role="status" style={{ marginTop: 24 }}>No Mac is paired to {pet.name} yet, so its views don’t count. In the Gremlo menu bar on that Mac, press Pair and sign once with the owner’s wallet.</p>}
      <div className="me-hero">
        <div>
          <div className="eyebrow">Your pet · {species ? species.name : PRODUCT} · {stage}</div>
          <h1 className="dsp">{pet.name}</h1>
          <div className="mood"><span className={`pill ${mood.pill}`}><i />{mood.label}</span>{why && <span>{why}</span>}</div>
          <div className="actions">
            <a className="btn ghost" href={share} target="_blank" rel="noreferrer">Share this week on X</a>
            <a className="btn" href={`/me/card?pet=${encodeURIComponent(pet.name)}`} target="_blank" rel="noreferrer" style={{ padding: "0 4px", fontSize: 14 }}>See the share card →</a>
          </div>
        </div>
        {art}
      </div>

      <div className="grow" role="list" aria-label="Growth stage">
        {STAGES.map(([n, m, r], i) => (
          <div key={n} className={`st${n === stage ? " on" : ""}`} role="listitem" aria-current={n === stage || undefined}>
            <span className="art"><Pet species={sp.id} row={r} frame={0} scale={[0.28, 0.26, 0.3, 0.36][i]} /></span>
            <b>{n}</b><small>{n === stage && n !== "Egg" ? `${meals} meal${meals === 1 ? "" : "s"}` : m}</small>
          </div>
        ))}
      </div>
      <div style={{ height: 44 }} />
      <div className="flow c3 tight">
        <Tile label="This week" value={week} sub={`for ${pet.week.views} views`} why="Can’t read this week’s settlements right now." />
        <Tile label="Paid by brands, all time" value={pet.paidViews == null ? null : near(pet.earnedWei)} sub={`for ${pet.paidViews} views`} why="Can’t read the payout record right now." />
        <Tile label="Level" value={pet.level == null ? null : String(pet.level)} sub="just for fun" why="Unknown until the record is readable." />
        <Tile label="Streak" value={`${pet.streak} day${pet.streak === 1 ? "" : "s"}`} sub={pet.streak ? "just for fun" : "starts with your next session"} />
        <Tile label="Views today" value={String(pet.impressionsToday)} sub="verified views" />
        <Tile label="Mood" value={mood.label} sub={why} />
      </div>
      <p className="muted" style={{ fontSize: 14, margin: "18px 0 0" }}>
        Earnings come from settlements, paid to <a className="hash" href={addressLink(pet.payout)} target="_blank" rel="noreferrer">{pet.payout}</a>. The streak and level are just for fun and never change what you’re paid.
      </p>

      <div className="sub-head">
        <div><div className="eyebrow">Meals</div><h2>{pet.purse ? "The pet’s purse" : "The compute budget"}</h2></div>
        <span className="n">{pet.purse ? `at most ${near(pet.purse.perCall)} a thought` : c ? `${c.shareBps / 100}% of every settlement` : "—"}</span>
      </div>
      <p className="muted" style={{ margin: "0 0 20px" }}>
        {pet.purse
          ? "The pet pays for each thought from its own purse, within caps its owner sets. Nobody else can spend from it, and every payment has a receipt and the call’s completion ID below."
          : <>A share of every settlement ({c ? `${c.shareBps / 100}%` : "—"}) stays with the pet as its compute budget. Each thought is charged a fixed rate per tier, not the provider’s real bill, and every charge has a receipt and the call’s completion ID below.</>}
      </p>
      {budget}

      <div className="proof-head"><h3>Proof · last thoughts</h3><span className="mono faint" style={{ fontSize: 12 }}>every call is paid from the pet’s own budget</span></div>
      {pet.lastThoughts.length === 0 ? (
        <div className="panel empty-box" style={{ padding: 32 }}>
          <Pet species={sp.id} row="idle" scale={0.5} />
          <p>No thoughts yet. They appear here the first time the pet thinks while your agent works.</p>
        </div>
      ) : (
        <table className="tbl">
          <thead><tr><th>When</th><th>Action</th><th>Model</th><th>Completion id</th><th>Charge</th></tr></thead>
          <tbody>
            {pet.lastThoughts.map((t) => (
              <tr key={t.requestId + t.at}>
                <td data-th="When">{formatWhen(t.at * 1000)}</td>
                <td data-th="Action">{t.action}</td>
                <td data-th="Model" className="m">{t.model ?? "–"}</td>
                <td data-th="Completion id" className="m wide">{t.requestId}</td>
                <td data-th="Charge" className="wide">{t.chargeTx ? <a className="hash" href={txLink(t.chargeTx)} target="_blank" rel="noreferrer">{t.chargeTx.slice(0, 8)}…{t.chargeTx.slice(-4)}</a> : <span className="faint">– not charged</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {/* the only place on this page that names the network, contract and provider (product copy names no chain) */}
      <details className="panel" style={{ marginTop: 40 }}>
        <summary className="lbl" style={{ cursor: "pointer" }}>Advanced · technical details</summary>
        <dl className="kvs" style={{ marginTop: 16 }}>
          <dt>Network</dt><dd>NEAR {NETWORK}</dd>
          <dt>Pet account</dt><dd className="mono">{pet.petKey}</dd>
          <dt>Owner</dt><dd><a className="hash" href={addressLink(pet.owner)} target="_blank" rel="noreferrer">{pet.owner}</a></dd>
          <dt>Payout</dt><dd><a className="hash" href={addressLink(pet.payout)} target="_blank" rel="noreferrer">{pet.payout}</a></dd>
          {pet.purse && <><dt>Purse</dt><dd><a className="hash" href={addressLink(pet.purse.account)} target="_blank" rel="noreferrer">{pet.purse.account}</a></dd></>}
          <dt>Contract</dt><dd>{pet.vault ? <a className="hash" href={addressLink(pet.vault)} target="_blank" rel="noreferrer">{pet.vault}</a> : "—"}</dd>
          <dt>Thinking</dt><dd>NEAR AI Cloud (private inference). {pet.purse ? "Each call is paid in NEAR from the pet’s purse with pay_inference, signed by the Mac’s purse key, and checked on chain before it counts." : "Each call is charged a fixed per-tier rate in NEAR from the pet’s compute budget, with its completion id in the contract’s log."}</dd>
        </dl>
      </details>
    </div>
  );
}
