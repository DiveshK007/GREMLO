import type { CSSProperties, ReactNode } from "react";

export const PROOF_MD = "https://github.com/DiveshK007/GREMLO/blob/main/PROOF.md";

/** One animated row of the pet's sheet, stepped in CSS. fw is the drawn frame width; sheet cells are 192x208. */
export function Spr({ row, n, fw = 72, slow, style }: { row: number; n: number; fw?: number; slow?: boolean; style?: CSSProperties }) {
  const k = fw / 192;
  return (
    <div
      aria-hidden="true"
      className="xp-spr"
      style={{ "--n": n, "--fw": `${fw}px`, width: fw, height: 208 * k, backgroundSize: `${1536 * k}px ${8112 * k}px`, backgroundPosition: `0 ${-row * 208 * k}px`, animationDuration: slow ? "2.4s" : undefined, ...style } as CSSProperties}
    />
  );
}

export const LiveDot = () => <span className="xp-dot" aria-hidden="true" />;

/** What a live block shows when its read failed. Never a stand-in number. */
export function Down({ children }: { children?: ReactNode }) {
  return (
    <div className="xp-down" role="status">
      <b>Live data unavailable right now</b>
      {children ?? null} <a href={PROOF_MD} target="_blank" rel="noreferrer">PROOF.md ↗</a>
    </div>
  );
}

export const Tick = ({ c = "#B48CFF", w = 2.2 }: { c?: string; w?: number }) => (
  <svg aria-hidden="true" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>
);
