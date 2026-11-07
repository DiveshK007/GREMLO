"use client";

import { useEffect, useState } from "react";
import { Sprite } from "./PetArt";

/** The pet holding its sign, cycling through hooks the way the Mac app rotates them. */
export function HookTicker({ hooks, scale = 1.5, every = 2800, label }: { hooks: string[]; scale?: number; every?: number; label?: string }) {
  const [i, setI] = useState(0);
  useEffect(() => {
    if (hooks.length < 2) return;
    const t = setInterval(() => setI((n) => (n + 1) % hooks.length), every);
    return () => clearInterval(t);
  }, [hooks.length, every]);
  const text = hooks[i % Math.max(hooks.length, 1)] ?? "";
  return (
    <figure className="ticker">
      <div className="ticker-board" aria-live="polite">
        <span className="ticker-tag">Sponsored</span>
        <span key={i} className="ticker-text">{text}</span>
      </div>
      <Sprite row={6} frames={6} scale={scale} />
      {label && <figcaption className="mono">{label}</figcaption>}
    </figure>
  );
}
