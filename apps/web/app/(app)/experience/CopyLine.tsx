"use client";

import { useState } from "react";

export function CopyLine({ text }: { text: string }) {
  const [done, setDone] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setDone(true);
      setTimeout(() => setDone(false), 1800);
    } catch {
      /* no clipboard (insecure origin, denied): the sentence is on screen to select */
    }
  }
  return (
    <>
      <button type="button" className="xp-copy" onClick={copy}>
        {done ? "Copied" : "Copy it"}
      </button>
      <span className="xp-sr" role="status">
        {done ? "Copied to the clipboard" : ""}
      </span>
    </>
  );
}
