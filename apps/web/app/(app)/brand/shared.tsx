"use client";

import { useEffect, useState } from "react";
import type { Brief } from "@/lib/api";
import type { readCampaign } from "@/lib/chain";
import { txLink } from "@/lib/config";
import { Plate } from "@/components/Plate";
import { useRotate } from "@/components/useRotate";

export const MIN_HOOK = 6,
  MAX_HOOK = 40; // the plate shows a line whole, never truncated or scrolled (R2 §2)
export const MIN_PICK = 1,
  MAX_PICK = 4; // up to 4 lines per campaign for the A/B test (R2 §15)
export const PREVIEW = "pip"; // the preview pet; brands don't pick one, every species carries lines
export const FORMAT_LABEL: Record<string, string> = {
  humour: "Humour",
  sarcasm: "Sarcasm",
  offer: "Irresistible offer",
  question: "Question",
  "bold-claim": "Bold claim",
  urgency: "Urgency",
  story: "Mini story",
  "dev-meme": "Dev meme",
  own: "Your own",
};
export const MOMENTS: [string, string][] = [
  ["any", "any time"],
  ["tests", "while tests run"],
  ["deploy", "during a deploy"],
  ["long run", "on a long run"],
];

export type Funded = { campaignId: bigint; txHash: string; hooks: string[]; budgetWei: bigint; rateWei: bigint; endTime: bigint; recordWarning?: string };
export type Lookup = Awaited<ReturnType<typeof readCampaign>>;
export const emptyBrief: Brief = { product: "", audience: "", offer: "", proof: "", cta: "" };
const short = (h: string) => (h.length > 20 ? `${h.slice(0, 10)}…${h.slice(-6)}` : h);
export const Tx = ({ hash, full }: { hash: string; full?: boolean }) => (
  <a className="hash" href={txLink(hash)} target="_blank" rel="noreferrer">
    {full ? hash : short(hash)}
  </a>
);

/** Seconds since mount, so a long AI call visibly moves. */
export function Elapsed() {
  const [s, setS] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setS((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  return <span className="secs">{s}s</span>;
}

export function Field({
  id,
  label,
  value,
  onChange,
  max = 160,
  opt,
  ph,
  hint,
  area,
  suffix,
  bad,
  type,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
  max?: number;
  opt?: boolean;
  ph?: string;
  hint?: string;
  area?: boolean;
  suffix?: string;
  bad?: boolean;
  type?: string;
}) {
  const props = { id, value, maxLength: max, placeholder: ph, "aria-invalid": bad || undefined, onChange: (e: { target: { value: string } }) => onChange(e.target.value) };
  const input = area ? <textarea {...props} /> : <input {...props} type={type} inputMode={suffix ? "decimal" : undefined} />;
  return (
    <div className="field" data-invalid={bad || undefined}>
      <label htmlFor={id}>
        {label}
        {opt && (
          <>
            {" "}
            <span className="opt">(optional)</span>
          </>
        )}
      </label>
      {suffix ? (
        <div className="suffix">
          {input}
          <span>{suffix}</span>
        </div>
      ) : (
        input
      )}
      {hint && <p className="hint">{hint}</p>}
    </div>
  );
}

export function ReceiptStage({ lines }: { lines: string[] }) {
  const line = useRotate(lines);
  return (
    <div className="stage receipt-stage">
      {line && (
        <span style={{ marginBottom: 20 }}>
          <Plate species={PREVIEW} line={line} brand="your brand" scale={0.7} k={5} />
        </span>
      )}
      <span className="cap lbl">Preview · what developers see</span>
    </div>
  );
}

export function DashPreview({ lines }: { lines: string[] }) {
  const line = useRotate(lines);
  return (
    <div className="stage" style={{ height: 200 }}>
      {line && (
        <span style={{ marginBottom: 14 }}>
          <Plate species={PREVIEW} line={line} scale={0.5} k={3.5} />
        </span>
      )}
    </div>
  );
}
