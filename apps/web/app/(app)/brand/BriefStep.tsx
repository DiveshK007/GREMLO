"use client";

import { Pet } from "@/components/Pet";
import { Elapsed, Field } from "./shared";
import type { Funding } from "./useFunding";

export function BriefStep({ f }: { f: Funding }) {
  const { brief, url, setUrl, attest, setAttest, hooks, dropped, hooksError, setField, onHooks, aiHooks, briefBad, busy } = f;
  return (
    <section className="step" id="s1">
      <div className="sub-head">
        <div>
          <div className="eyebrow">Your brief</div>
          <h2>
            <span className="num">01</span>Your product
          </h2>
        </div>
        <span className="n">the pet writes from this, nothing else</span>
      </div>
      <Field id="what" label="What is it?" value={brief.product} onChange={setField("product")} ph="Clearlog, log search for TypeScript teams" bad={!!briefBad && !brief.product.trim()} />
      <div className="grid2">
        <Field id="who" label="Who is it for?" value={brief.audience} onChange={setField("audience")} max={120} ph="backend developers" bad={!!briefBad && !brief.audience.trim()} />
        <Field id="offer" label="Offer" value={brief.offer} onChange={setField("offer")} max={120} opt ph="first 1M logs free" />
      </div>
      <Field
        id="proof"
        label="Proof points"
        value={brief.proof}
        onChange={setField("proof")}
        area
        max={600}
        opt
        ph={"Searches a day of logs in 80ms\nUsed by 400 TypeScript teams"}
        hint="One per line. Hooks may only use numbers and claims from here. Promises of returns or profit are never allowed."
      />
      <div className="grid2">
        <Field id="cta" label="Call to action" value={brief.cta} onChange={setField("cta")} max={40} ph="Try it free" bad={!!briefBad && !brief.cta.trim()} />
        <Field id="link" label="Link" value={url} onChange={setUrl} max={300} ph="https://" bad={!!briefBad && !/^https:\/\/[^\s]+\.[^\s]+/.test(url.trim())} />
      </div>
      <label className="check">
        <input type="checkbox" checked={attest} onChange={(e) => setAttest(e.target.checked)} />
        <span>These proof points are our own claims, and they’re accurate.</span>
      </label>
      {busy === "hooks" ? (
        <div className="panel writing" role="status">
          <Pet species="byte" row="tools" fps={7} scale={0.42} />
          <p>
            <b>Writing 16 hooks…</b>Then every hook is checked against your proof points. This can take up to two minutes.
          </p>
          <Elapsed />
        </div>
      ) : (
        <div className="actions">
          <button type="button" className={`btn ${aiHooks.length ? "ghost" : "solid"}`} onClick={onHooks}>
            {aiHooks.length ? "Write new hooks" : "Write my hooks"}
          </button>
        </div>
      )}
      {hooksError && !(hooks.length || dropped.length) && (
        <div className="bad" role="alert">
          {hooksError}
        </div>
      )}
    </section>
  );
}
