"use client";

import { FORMAT_LABEL, MAX_HOOK, MAX_PICK, MIN_HOOK, MIN_PICK, MOMENTS } from "./shared";
import type { Funding } from "./useFunding";

export function HookStep({ f }: { f: Funding }) {
  const { hooksError, filter, setFilter, formats, allDropped, groups, picked, n, toggle, moments, setMoments, dropped, own, setOwn, ownLen, onAddOwn } = f;
  return (
    <section className="step" id="s2">
      <div className="sub-head">
        <div>
          <div className="eyebrow">Your lines</div>
          <h2>
            <span className="num">02</span>Pick {MIN_PICK} to {MAX_PICK} hooks
          </h2>
        </div>
        <span className="n" role="status">
          Picked {n} of {MAX_PICK}
        </span>
      </div>
      <p className="muted" style={{ margin: "0 0 6px", fontSize: 14.5 }}>
        Traffic is even until each line has 2,000 sightings, then favours the lines developers open.
      </p>
      {hooksError && (
        <div className="bad" role="alert">
          {hooksError}
        </div>
      )}
      {formats.length > 1 && (
        <div className="seg sm" role="group" aria-label="Filter by format" style={{ marginTop: 16 }}>
          <button type="button" aria-pressed={filter === "all"} onClick={() => setFilter("all")}>
            All
          </button>
          {formats.map((f) => (
            <button key={f} type="button" aria-pressed={filter === f} onClick={() => setFilter(f)}>
              {FORMAT_LABEL[f]}
            </button>
          ))}
        </div>
      )}
      {allDropped && (
        <div className="panel" style={{ marginTop: 18 }}>
          <b style={{ color: "var(--fg)" }}>None of the hooks passed the claim checks.</b>
          <p className="muted" style={{ margin: "6px 0 0", fontSize: 14 }}>
            Usually the proof points are too thin. Add a number you can stand behind, then write again, or write your own below.
          </p>
        </div>
      )}
      {groups.map(({ f, list }) => (
        <div key={f}>
          <div className="fmt">{FORMAT_LABEL[f]}</div>
          <div className="lines">
            {list.map((h) => {
              const on = picked.includes(h.text);
              return (
                <button key={h.text} type="button" className="line" aria-pressed={on} disabled={!on && n >= MAX_PICK} onClick={() => toggle(h.text)}>
                  <span className="box" />
                  <span className="tx">
                    <b>{h.text}</b>
                    <small>
                      <span>{h.requestId ? `written by AI · ${h.requestId}` : "written by you"}</span>
                      <span>
                        {h.text.length}/{MAX_HOOK}
                      </span>
                    </small>
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      ))}
      {n > 0 && (
        <>
          <div className="fmt">When should each line show?</div>
          <p className="muted" style={{ margin: "0 0 6px", fontSize: 14 }}>
            The pet works out the moment on the developer’s Mac; nothing about their work is sent.
          </p>
          <div className="moments">
            {picked.map((line) => (
              <div key={line} className="moment">
                <b>{line}</b>
                <div className="seg sm" role="group" aria-label={`Moment for “${line}”`}>
                  {MOMENTS.map(([k, l]) => (
                    <button key={k} type="button" aria-pressed={(moments[line] ?? "any") === k} onClick={() => setMoments({ ...moments, [line]: k })}>
                      {l}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </>
      )}
      {dropped.length > 0 && (
        <details className="dropped" open={allDropped}>
          <summary>
            {dropped.length} hook{dropped.length === 1 ? "" : "s"} didn’t pass the claim checks
          </summary>
          <ul>
            {dropped.map((d, i) => (
              <li key={i}>
                {d.text} <span>— {d.reason}</span>
              </li>
            ))}
          </ul>
        </details>
      )}
      <div className="fmt" style={{ marginTop: 30 }}>
        Write your own
      </div>
      <div className="field" style={{ maxWidth: 560 }}>
        <label htmlFor="own" className="sr">
          Your own line
        </label>
        <div className="inline">
          <input
            id="own"
            value={own}
            onChange={(e) => setOwn(e.target.value)}
            maxLength={MAX_HOOK}
            placeholder={`${MIN_HOOK} to ${MAX_HOOK} characters`}
            disabled={n >= MAX_PICK}
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                e.preventDefault();
                onAddOwn();
              }
            }}
            aria-describedby="ownc"
          />
          <button type="button" className="btn ghost sm" style={{ minHeight: 54 }} onClick={onAddOwn} disabled={!own.trim() || n >= MAX_PICK}>
            Add
          </button>
        </div>
        <span id="ownc" className={`count${ownLen > 0 && ownLen < MIN_HOOK ? " over" : ""}`}>
          {ownLen}/{MAX_HOOK}
        </span>
        {n >= MAX_PICK && <p className="hint">You’ve picked {MAX_PICK}. Unpick one to add your own.</p>}
      </div>
    </section>
  );
}
