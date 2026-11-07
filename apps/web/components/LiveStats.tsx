"use client";

import { useEffect, useRef, useState } from "react";
import { formatEther } from "viem";
import { publicStats, type PublicStats } from "@/lib/api";

/** Counts up to a real number once visible. */
function Count({ to, decimals = 0 }: { to: number; decimals?: number }) {
  const [v, setV] = useState(0);
  const ref = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => {
      if (!e.isIntersecting) return;
      io.disconnect();
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return setV(to);
      const t0 = performance.now();
      const tick = (t: number) => { const p = Math.min(1, (t - t0) / 1200); setV(to * (1 - (1 - p) ** 3)); if (p < 1) requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
    });
    io.observe(el);
    return () => io.disconnect();
  }, [to]);
  return <span ref={ref}>{v.toFixed(decimals)}</span>;
}

/** Live numbers from the chain's events. A dash means the server could not be reached, never a zero. */
export function LiveStats() {
  const [s, setS] = useState<PublicStats | null | undefined>(undefined);
  useEffect(() => { publicStats().then(setS).catch(() => setS(null)); }, []);
  const cell = (label: string, value: React.ReactNode) => <li><span className="mono">{label}</span><strong>{value}</strong></li>;
  const dash = s === null ? "–" : "…";
  return (
    <ul className="stats live-stats">
      {cell("Campaigns funded", s ? <Count to={s.campaigns} /> : dash)}
      {cell("Views settled onchain", s ? <Count to={Number(s.settledViews)} /> : dash)}
      {cell("Paid to developers", s ? <><Count to={Number(formatEther(BigInt(s.paidWei)))} decimals={4} /> 0G</> : dash)}
      {cell("Verified pets", s ? <Count to={s.pets} /> : dash)}
    </ul>
  );
}
