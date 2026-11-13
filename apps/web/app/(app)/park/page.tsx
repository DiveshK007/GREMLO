"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { parkPets, type ParkPet } from "@/lib/api";
import { speciesOf, type RowName } from "@/lib/species";
import { Pet, type PetHandle } from "@/components/Pet";
import { useAccent, useNotch } from "@/components/Shell";
import "./park.css";

// R4 §14: opt-in, random order on every load (the server shuffles), no ranking and no counts. Each pet shows only its
// name, species, stage, today's outfit, and the tricks it learned, so a tap can show one off. Never an ad.

const TRICKS = ["backflip", "juggle", "moonwalk"] as const;
const LANES = [0.3, 0.06, 0.22, 0, 0.16, 0.11, 0.26, 0.03, 0.19, 0.08, 0.13, 0.24];
const cap = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);
const outfitLine = (p: ParkPet) => cap(p.stage) + (p.outfit.length ? ` · ${p.outfit.join(", ")}` : "");
const trickOf = (p: ParkPet) => (p.tricks ?? []).find((t): t is (typeof TRICKS)[number] => (TRICKS as readonly string[]).includes(t)) ?? null;

type Walk = { x: number; dir: number; v: number; stop: boolean; arc: number | null; slide: boolean };

function Yard({ pets, mode, picked, onPick }: { pets: ParkPet[]; mode: "pets" | "loading" | "empty" | "error"; picked: string | null; onPick: (p: ParkPet) => void }) {
  const yard = useRef<HTMLDivElement>(null);
  const [small, setSmall] = useState(false);
  useEffect(() => { setSmall(window.innerWidth < 600); }, []);
  const shown = pets.slice(0, small ? 5 : 12);
  const scale = small ? 0.34 : 0.42;
  const btns = useRef<(HTMLButtonElement | null)[]>([]);
  const sprites = useRef<(PetHandle | null)[]>([]);
  const walks = useRef<Walk[]>([]);

  // one loop moves every walker; a trick stops it in place, the backflip adds the jump arc (0.5 s, 1.6 body heights)
  useEffect(() => {
    const W = () => yard.current?.clientWidth ?? 800;
    walks.current = shown.map((_, i) => ({ x: (i / shown.length) * (W() + 140) - 80, dir: i % 3 === 1 ? -1 : 1, v: 26 + ((i * 7) % 22), stop: false, arc: null, slide: false }));
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let last = performance.now(), raf = 0;
    const step = (now: number) => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const w = W();
      walks.current.forEach((o, i) => {
        const el = btns.current[i];
        if (!el) return;
        if (o.slide && !still) o.x -= o.dir * 30 * dt; // moonwalk: slides backwards while it faces forwards
        else if (!o.stop && !still) o.x += o.dir * o.v * dt;
        if (o.x > w + 30) o.x = -150;
        if (o.x < -150) o.x = w + 30;
        let y = 0;
        if (o.arc != null) {
          const t = (now - o.arc) / 500;
          if (t >= 1) o.arc = null; else y = -Math.sin(Math.PI * t) * 1.6 * 208 * scale * 0.55;
        }
        el.style.transform = `translate(${o.x.toFixed(1)}px, ${y.toFixed(1)}px)`;
        const cv = el.querySelector("canvas");
        if (cv) cv.style.transform = o.dir < 0 ? "scaleX(-1)" : "";
      });
      raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [shown.map((p) => p.id).join(","), scale]); // eslint-disable-line react-hooks/exhaustive-deps

  function tap(p: ParkPet, i: number) {
    onPick(p);
    const o = walks.current[i], s = sprites.current[i];
    if (!o || !s) return;
    const trick = trickOf(p);
    o.stop = true;
    const back = () => { o.stop = false; o.slide = false; s.play("walk", { fps: 8 }); };
    if (trick === "backflip") { o.arc = performance.now(); s.play("backflip", { fps: 10, loop: false, onEnd: back }); }
    else if (trick === "moonwalk") { o.slide = true; s.play("moonwalk", { fps: 7, frames: [0, 1, 2, 3, 0, 1, 2, 3], loop: false, onEnd: back }); }
    else if (trick === "juggle") s.play("juggle", { fps: 7, frames: [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3], loop: false, onEnd: back });
    else s.play("greet", { fps: 8, loop: false, onEnd: back });
  }

  return (
    <div ref={yard} className={`park${mode === "error" ? " dim" : ""}`} role="group" aria-label={`The park.${shown.length ? ` ${shown.length} pets walking; tap one.` : ""}`}>
      <i className="tree" style={{ left: "5%" }} /><i className="tree" style={{ left: "33%", transform: "scale(1.3)" }} />
      <i className="tree" style={{ left: "64%", transform: "scale(.9)" }} /><i className="tree" style={{ left: "86%", transform: "scale(1.15)" }} />
      {Array.from({ length: 24 }, (_, i) => <i key={i} className="star" style={{ left: `${(i * 37) % 100}%`, top: `${(i * 17) % 46}%` }} />)}
      {mode === "loading" && <div className="msg" role="status"><span className="spin" />Opening the gates…</div>}
      {mode === "empty" && <><span className="bench" /><div className="msg"><b style={{ fontSize: 20 }}>Nobody is out right now.</b><span style={{ opacity: 0.75 }}>Pets show up when their owners turn the park on. Check back later.</span></div></>}
      {mode === "error" && <div className="msg"><b style={{ fontSize: 20 }}>Can’t reach the park right now.</b></div>}
      {mode === "pets" && shown.map((p, i) => {
        const sp = speciesOf(p.species), b = Math.round(LANES[i] * 100);
        return (
          <button key={p.id} ref={(el) => { btns.current[i] = el; }} type="button" className="walker" style={{ bottom: `${b}%`, zIndex: 100 - b }}
            aria-pressed={picked === p.id} aria-label={`${p.name}, a ${p.stage}. ${trickOf(p) ? "Tap for a trick." : "Tap to say hi."}`} onClick={() => tap(p, i)}>
            <span className="tag">{p.name} <em>· {sp.name} · {cap(p.stage)}</em></span>
            <Pet ref={(h) => { sprites.current[i] = h; }} species={sp.id} row="walk" fps={8} scale={scale} />
          </button>
        );
      })}
    </div>
  );
}

function Picked({ p }: { p: ParkPet }) {
  const sp = speciesOf(p.species), trick = trickOf(p);
  const row: RowName = trick ?? "greet";
  return (
    <div className="panel picked" aria-live="polite">
      <Pet species={sp.id} row={row} fps={7} scale={0.62} />
      <div>
        <div className="eyebrow" data-pet={sp.id}>{sp.name} · {cap(p.stage)}</div>
        <h2 className="dsp">{p.name}</h2>
        <p>{trick ? `Showing off a trick it learned: ${trick}.` : "Says hi. It hasn’t learned a trick yet."}{p.outfit.length ? ` Wearing ${p.outfit.join(", ")} today.` : ""}</p>
      </div>
      <div className="go">
        <a className="btn solid" href={`gremlo://visit?to=${encodeURIComponent(p.id)}`}>Send my pet to visit</a>
        <small>Opens the Gremlo app on your Mac. Without the app installed, nothing happens: <Link href="/pet">get your pet</Link> first.</small>
      </div>
    </div>
  );
}

export default function Park() {
  useAccent("byte");
  const notch = useNotch();
  const [pets, setPets] = useState<ParkPet[] | null>(null);
  const [error, setError] = useState("");
  const [picked, setPicked] = useState<ParkPet | null>(null);

  async function load() {
    setError("");
    setPets(null);
    notch.set("think");
    try { setPets((await parkPets()).pets ?? []); } catch (e) { setError((e as Error).message); }
    notch.base("rest");
  }
  useEffect(() => { void load(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const mode = error ? "error" : pets == null ? "loading" : pets.length ? "pets" : "empty";
  return (
    <>
      <div className="wrap">
        <div className="sec-head">
          <div><div className="eyebrow">The pet park</div><h1 className="dsp">Everyone’s pets, out for a walk.</h1></div>
          <p>Pets whose owners chose to show them. Random order every time; nobody is ranked. Tap one to say hi.</p>
        </div>
      </div>
      <div className="wrap">
        <Yard pets={pets ?? []} mode={mode} picked={picked?.id ?? null} onPick={setPicked} />
        {error && <><div className="bad" role="alert" style={{ marginTop: 16 }}>Can’t reach the park right now. <span className="mono faint" style={{ fontSize: 12.5 }}>{error}</span></div><button type="button" className="btn ghost sm" style={{ marginTop: 6 }} onClick={load}>Try again</button></>}
        {picked && <Picked p={picked} />}
        {mode === "loading" && <><div className="sub-head"><h2 style={{ fontSize: 20 }}>Everyone out now</h2></div><div className="everyone">{Array.from({ length: 6 }, (_, i) => <div key={i} className="skel" />)}</div></>}
        {mode === "pets" && pets && (
          <>
            <div className="sub-head"><h2 style={{ fontSize: 20 }}>Everyone out now</h2><span className="n">{pets.length} pet{pets.length === 1 ? "" : "s"} · shuffled on every visit</span></div>
            <div className="everyone">
              {pets.map((p) => (
                <button key={p.id} type="button" className="tile" aria-pressed={picked?.id === p.id} aria-label={`${p.name}, a ${p.stage}`} onClick={() => setPicked(p)}>
                  <span className="art"><Pet species={p.species} row="idle" frame={0} scale={0.34} /></span>
                  <b>{p.name}</b><small>{outfitLine(p)}</small>
                </button>
              ))}
            </div>
          </>
        )}
        <div className="parkrules">
          <div><b>Pets only</b><p>Name, species, stage and today’s outfit. No owner, no handle, no stats.</p></div>
          <div><b>No ranking</b><p>Random order on every load. No leaderboard, no counts, no “most active”.</p></div>
          <div><b>Tricks are earned</b><p>Backflip, juggle, moonwalk come from milestones, never bought.</p></div>
          <div><b>Never an ad</b><p>No sponsored line ever appears in the park.</p></div>
        </div>
        <div className="join"><Pet row="sit" fps={3} scale={0.3} /><p>To join, turn on “Show my pet in the park” in the Mac app’s settings. Leaving removes your pet at the next refresh.</p></div>
      </div>
    </>
  );
}
