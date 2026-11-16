"use client";

import { useEffect, useState } from "react";
import { Spr } from "./parts";

const STEPS = [
  { num: "01", tag: "IDLE", title: "It waits in the notch", body: "Hidden until your agent has something to do.", color: "#F4F2ED" },
  { num: "02", tag: "AGENT WORKING", title: "It holds one sponsored line", body: "Only while your agent works, always labelled AD. Each 5-second view on screen is signed by your Mac.", color: "#D97757" },
  { num: "03", tag: "RISKY COMMAND", title: "It knocks before risky commands", body: "You allow or deny right from the notch, before anything runs.", color: "#FFC93C" },
  { num: "04", tag: "RUN DONE", title: "It celebrates with you", body: "Confetti, a time, and back to its corner.", color: "#8FD14F" },
];
const CONFETTI: [number, string, number][] = [[6, "#FF5A3C", 0], [20, "#FFC93C", .3], [34, "#2ED3B7", .6], [62, "#B48CFF", .15], [78, "#4CC9FF", .45], [92, "#8FD14F", .75]];

/** The four-state notch demo. `line` is the live campaign line, or null when it could not be read. */
export function Demo({ line, campaignId }: { line: string | null; campaignId: string | null }) {
  const [step, setStep] = useState(1);
  const [auto, setAuto] = useState(true);

  useEffect(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) setAuto(false);
  }, []);
  useEffect(() => {
    if (!auto) return;
    const t = setInterval(() => setStep((s) => (s + 1) % 4), 3400);
    return () => clearInterval(t);
  }, [auto]);

  return (
    <div className="xp-demo">
      <figure className="xp-mac">
        <div className="xp-screen">
          <div className="xp-menubar" aria-hidden="true"><span>Terminal</span><span>Shell</span><span>Edit</span><span>View</span><span style={{ marginLeft: "auto" }}>Mon 15:30</span></div>
          <div className="xp-term">
            <div className="xp-term-bar" aria-hidden="true"><i style={{ background: "#FF5F57" }} /><i style={{ background: "#FEBC2E" }} /><i style={{ background: "#28C840" }} /><span>~/vault — claude</span></div>
            <div className="xp-term-body">
              <div>❯ claude &quot;refactor the vault withdraw path&quot;</div>
              {step === 0 && <div style={{ color: "rgba(244,242,237,.62)" }}>waiting for you<span className="xp-caret">▍</span></div>}
              {step === 1 && <div className="xp-rise"><div>⏺ Reading src/vault.rs, src/withdraw.rs</div><div style={{ color: "#D97757" }}>✻ Thinking… <span style={{ color: "rgba(244,242,237,.62)" }}>(2m 14s · esc to interrupt)</span></div></div>}
              {step === 2 && <div className="xp-rise"><div>⏺ Bash(rm -rf ./build)</div><div style={{ color: "#FFC93C" }}>⏸ Waiting for your permission</div></div>}
              {step === 3 && <div className="xp-rise"><div style={{ color: "#8FD14F" }}>✓ 3 files changed · 21 tests pass</div><div style={{ color: "rgba(244,242,237,.62)" }}>Done in 4m 12s</div></div>}
            </div>
          </div>

          <div className="xp-notch-layer">
            {step === 0 && (
              <div className="xp-col">
                <div className="xp-pop xp-pill" style={{ width: 190, height: 32, borderRadius: "0 0 16px 16px" }} />
                <Spr row={14} n={4} style={{ marginTop: -40 }} />
              </div>
            )}
            {step === 1 && (
              <div className="xp-col">
                <div className="xp-pop xp-pill" style={{ width: 300, height: 40, borderRadius: "0 0 18px 18px", boxShadow: "0 0 0 2px #D97757, 0 10px 40px rgba(217,119,87,.45)" }}>✻ Claude Code · thinking</div>
                <div className="xp-col" style={{ marginTop: 6 }}>
                  <Spr row={6} n={6} />
                  {line && <div className="xp-pop xp-sign" style={{ marginTop: -6 }}><span className="xp-ad">AD</span>{line}</div>}
                </div>
              </div>
            )}
            {step === 2 && (
              <div className="xp-pop xp-ask">
                <Spr row={3} n={4} style={{ flex: "none" }} />
                <div className="xp-ask-body">
                  <div style={{ fontSize: 13, color: "rgba(244,242,237,.78)" }}>Claude Code wants to run</div>
                  <div style={{ fontFamily: "var(--mono)", fontSize: 15, color: "#FFC93C" }}>rm -rf ./build</div>
                  <div style={{ display: "flex", gap: 8 }}>
                    <button type="button" className="xp-deny">Deny</button>
                    <button type="button" className="xp-allow">Allow once</button>
                  </div>
                </div>
              </div>
            )}
            {step === 3 && (
              <div className="xp-col" style={{ position: "relative" }}>
                <div className="xp-pop xp-pill" style={{ width: 300, height: 40, borderRadius: "0 0 18px 18px", boxShadow: "0 0 0 2px #8FD14F, 0 10px 40px rgba(143,209,79,.4)" }}>Done in 4m 12s</div>
                <Spr row={4} n={5} style={{ marginTop: 4 }} />
                <div aria-hidden="true" className="xp-confetti">{CONFETTI.map(([x, c, d]) => <span key={x} className="xp-conf" style={{ left: `${x}%`, background: c, animationDelay: `${d}s` }} />)}</div>
              </div>
            )}
          </div>
          <span className="xp-example">EXAMPLE · HOW IT LOOKS ON A MAC</span>
        </div>
        <figcaption>
          {line ? <>Illustration of the Mac app. The sign shows the real line from campaign {campaignId}, “{line}”. </> : <>Illustration of the Mac app. The live campaign line could not be read right now, so no sign is drawn. </>}
          On a real Mac the pet stays out of full-screen apps and hides during screen sharing.
        </figcaption>
      </figure>

      <div className="xp-steps">
        {STEPS.map((s, i) => {
          const on = i === step;
          return (
            <button key={s.num} type="button" aria-pressed={on} className={`xp-step${on ? " on" : ""}`} style={{ borderColor: on ? s.color : undefined }} onClick={() => { setStep(i); setAuto(false); }}>
              <span className="xp-step-tag" style={{ color: on ? s.color : undefined }}>{s.num} · {s.tag}</span>
              <span className="xp-step-title">{s.title}</span>
              {on && <span className="xp-step-body">{s.body}</span>}
            </button>
          );
        })}
        <button type="button" className="xp-auto" onClick={() => setAuto(!auto)}>{auto ? "Pause the demo" : "Play the demo"}</button>
      </div>
    </div>
  );
}
