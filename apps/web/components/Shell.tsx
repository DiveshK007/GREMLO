"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { Pet } from "./Pet";
import { PRODUCT } from "@/lib/config";

// The shared bar, phone menu, footer and the notch (APP_PAGES_REDESIGN §1.4-1.6). The notch only ever reflects this
// page's own work: rest, peek on hover, think while a request runs, wait while you act elsewhere (wallet, phone),
// done for 2.4 s, egg and door on /pet. It never shows a sponsored line or anyone's data.

export type NotchState = "rest" | "think" | "wait" | "done" | "egg" | "door" | "sleep";
type Notch = { set: (s: NotchState, text?: string) => void; base: (s: NotchState) => void; species: (id: string | null) => void };
const NotchCtx = createContext<Notch>({ set: () => {}, base: () => {}, species: () => {} });
export const useNotch = () => useContext(NotchCtx);

/** Sets the page's accent (body[data-pet]) while the page is shown. */
export function useAccent(species: string | null | undefined) {
  useEffect(() => {
    const id = String(species ?? "gremlo").replace(/^gremlo-/, "");
    document.body.dataset.pet = id;
    return () => { document.body.dataset.pet = "gremlo"; };
  }, [species]);
}

const THEMES = ["system", "light", "dark"] as const;
type Theme = (typeof THEMES)[number];
function useTheme(): [Theme, (t: Theme) => void] {
  const [t, setT] = useState<Theme>("system");
  useEffect(() => {
    try { const s = localStorage.getItem("gremlo.theme"); if (s === "light" || s === "dark") setT(s); } catch {}
  }, []);
  const set = useCallback((next: Theme) => {
    setT(next);
    try { localStorage.setItem("gremlo.theme", next); } catch {}
    if (next === "system") delete document.documentElement.dataset.theme;
    else document.documentElement.dataset.theme = next;
  }, []);
  return [t, set];
}

let toastTimer: ReturnType<typeof setTimeout> | undefined;
/** A short bottom toast ("Link copied"), announced politely. */
export function toast(msg: string) {
  let el = document.querySelector<HTMLDivElement>(".toast");
  if (!el) {
    el = document.createElement("div");
    el.className = "toast";
    el.setAttribute("role", "status");
    el.setAttribute("aria-live", "polite");
    document.body.appendChild(el);
  }
  el.textContent = msg;
  el.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el!.classList.remove("on"), 2000);
}

const NAV: [string, string][] = [["/me", "Your pet"], ["/brand", "Fund a campaign"], ["/park", "Park"], ["/money", "Money"]];
const FOOT: [string, string][] = [["/", "Home"], ["/pet", "Get your pet"], ["/me", "Your pet"], ["/brand", "Fund a campaign"], ["/park", "Park"], ["/gallery", "Gallery"], ["/money", "Money"], ["/live", "Live numbers"]];
const ThemeIcon = () => (
  <svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2" fill="none" stroke="currentColor" strokeWidth="1.5" /><path d="M8 1.8a6.2 6.2 0 0 1 0 12.4z" fill="currentColor" /></svg>
);

function NotchView({ state, text, species }: { state: NotchState; text: string; species: string | null }) {
  const [hover, setHover] = useState(false);
  const shown = state === "rest" && hover ? "peek" : state;
  const eyes = <span className="eyes"><Pet species={species} row="peek" fps={2} scale={0.19} /></span>;
  return (
    <div className="notch" data-state={shown} role="status" aria-live="polite" onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <div className="nl nl-think"><i /><i /><i /></div>
      <div className="nl nl-peek">{eyes}<span className="pulse" /></div>
      <div className="nl nl-wait">{eyes}<span className="t">{text}</span><span className="pulse" /></div>
      <div className="nl nl-done">{eyes}<span className="t">{text}</span><span className="ok">✓</span></div>
      <div className="nl nl-egg"><span className="eggc"><Pet species={species} row="hatch" frames={[0, 1, 0, 2]} fps={4} scale={0.14} /></span><span>{text || "warming up"}</span><span className="pulse" /></div>
      <div className="nl nl-door">door open</div>
      <div className="nl nl-sleep"><span className="eyes"><Pet species={species} row="peek" frame={2} scale={0.19} /></span><span className="zz">z</span><span className="zz">z</span></div>
      <span className="sr">{text}</span>
    </div>
  );
}

export function Shell({ children }: { children: React.ReactNode }) {
  const path = usePathname() || "/";
  const min = path.startsWith("/pair");
  const [theme, setTheme] = useTheme();
  const [open, setOpen] = useState(false);
  const [state, setState] = useState<NotchState>("rest");
  const [text, setText] = useState("");
  const [species, setSpecies] = useState<string | null>(null);
  const base = useRef<NotchState>("rest");
  const doneT = useRef<ReturnType<typeof setTimeout>>();

  const notch = useMemo<Notch>(() => ({
    set(s, t = "") {
      clearTimeout(doneT.current);
      setState(s);
      setText(t);
      if (s === "done") doneT.current = setTimeout(() => { setState(base.current); setText(""); }, 2400);
    },
    base(s) { base.current = s; clearTimeout(doneT.current); setState(s); setText(""); },
    species: (id) => setSpecies(id),
  }), []);

  // a new page starts with a resting notch and a closed menu. Reset while rendering, not in an effect: a page's own
  // effects run before the layout's, so an effect here would wipe the notch state the page just set
  const [seenPath, setSeenPath] = useState(path);
  if (seenPath !== path) {
    setSeenPath(path);
    setOpen(false);
    setState("rest");
    setText("");
    base.current = "rest";
    clearTimeout(doneT.current);
  }
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    const esc = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(false); };
    addEventListener("keydown", esc);
    return () => removeEventListener("keydown", esc);
  }, [open]);

  const cur = (href: string) => (href === "/" ? path === "/" : path.startsWith(href)) ? { "aria-current": "page" as const } : {};
  const cycle = () => setTheme(THEMES[(THEMES.indexOf(theme) + 1) % 3]);

  return (
    <NotchCtx.Provider value={notch}>
      <header className={`bar${min ? " min" : ""}`}>
        <Link className="logo" href="/" aria-label={`${PRODUCT} home`}><i />{PRODUCT}</Link>
        <div className="notch-host"><NotchView state={state} text={text} species={species} /></div>
        <nav aria-label="Main">
          {!min && NAV.map(([h, l]) => <Link key={h} href={h} {...cur(h)}>{l}</Link>)}
          <button type="button" className="themebtn" onClick={cycle} aria-label={`Theme: ${theme}. Change theme`}><ThemeIcon /><span>{theme}</span></button>
          {!min && <Link className="btn solid" href="/pet" {...cur("/pet")}>Get your pet</Link>}
        </nav>
        {!min && (
          <button type="button" className="menubtn" aria-expanded={open} aria-controls="sheet" onClick={() => setOpen(!open)}><i />Menu</button>
        )}
      </header>
      {!min && (
        <div className={`sheet${open ? " open" : ""}`} id="sheet" role="dialog" aria-label="Menu" aria-hidden={!open}>
          {[["/pet", "Get your pet"] as [string, string], ...NAV].map(([h, l]) => <Link key={h} className="big" href={h} {...cur(h)}>{l}</Link>)}
          <div className="small">
            <Link href="/gallery" {...cur("/gallery")}>Gallery</Link>
            <Link href="/live" {...cur("/live")}>Live numbers</Link>
            <Link href="/">Home</Link>
          </div>
          <div className="lbl" style={{ marginTop: 30 }}>Theme</div>
          <div className="seg sm" style={{ marginTop: 10 }}>
            {THEMES.map((t) => <button key={t} type="button" aria-pressed={theme === t} onClick={() => setTheme(t)}>{t[0].toUpperCase() + t.slice(1)}</button>)}
          </div>
        </div>
      )}
      <main id="main">{children}</main>
      <footer className="foot">
        <div className="wrap">
          {min ? (
            <div><span className="brand">{PRODUCT}</span> · pairing is a one-time step. You can close this tab when it says done.</div>
          ) : (
            <>
              <div><span className="brand">{PRODUCT}</span> · a pet for every agent<br />All eight species are original. Seeded and example figures are labelled where they appear.</div>
              <nav aria-label="Footer">{FOOT.map(([h, l]) => <Link key={h} href={h} {...cur(h)}>{l}</Link>)}</nav>
            </>
          )}
        </div>
      </footer>
    </NotchCtx.Provider>
  );
}
