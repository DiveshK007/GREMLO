"use client";

import { useEffect, useState } from "react";

/** Cycles through lines the way the pet rotates them on its sign; holds the first under reduced motion. */
export function useRotate(lines: string[], every = 3200) {
  const [i, setI] = useState(0);
  const key = lines.join("\n");
  useEffect(() => {
    setI(0);
    if (lines.length < 2 || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const t = setInterval(() => setI((n) => (n + 1) % lines.length), every);
    return () => clearInterval(t);
  }, [key, every]); // eslint-disable-line react-hooks/exhaustive-deps
  return lines.length ? lines[i % lines.length] : null;
}
