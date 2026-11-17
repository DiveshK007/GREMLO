"use client";

import { Field } from "./shared";
import type { Funding } from "./useFunding";

export function BudgetStep({ f }: { f: Funding }) {
  const { hooks, budget, setBudget, rate, setRate, hours, setHours, endsAt, email, setEmail } = f;
  return (
    <section className="step" id="s3">
      <div className="sub-head">
        <div>
          <div className="eyebrow">Pay</div>
          <h2>
            <span className="num">03</span>Budget
          </h2>
        </div>
        {hooks.length > 0 && <span className="n">refunds whatever isn’t spent</span>}
      </div>
      {hooks.length === 0 ? (
        <p className="muted">Write or add a hook first. Budget opens after that.</p>
      ) : (
        <>
          <div className="grid3">
            <Field id="bud" label="Total budget" value={budget} onChange={setBudget} suffix="NEAR" />
            <Field id="ppv" label="Price per view" value={rate} onChange={setRate} suffix="NEAR" />
            <Field id="hrs" label="Runs for" value={hours} onChange={setHours} suffix="hours" />
          </div>
          <p className="note" style={{ marginTop: -6 }}>
            {Number(hours) > 0 ? `Ends ${endsAt || "…"}. Views can still be paid for 1 hour after that; then the unspent budget is refunded.` : "Enter the hours it should run."}
          </p>
          <Field id="em" label="Email for budget alerts and a weekly report" value={email} onChange={setEmail} max={254} opt type="email" hint="Only used to email you about this campaign. Never shown or shared." />
        </>
      )}
    </section>
  );
}
