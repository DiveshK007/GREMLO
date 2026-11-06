"use client";

import { useEffect, useState } from "react";
import { activeCampaign } from "@/lib/api";
import { Sprite } from "./PetArt";

/** The pet holding whatever line is live right now. No campaign means a plain invitation, never a made-up ad. */
export function LiveSign() {
  const [state, setState] = useState<{ kind: "loading" } | { kind: "live"; line: string } | { kind: "none" } | { kind: "offline" }>({ kind: "loading" });
  useEffect(() => {
    activeCampaign()
      .then((c) => setState(c?.line ? { kind: "live", line: c.line } : { kind: "none" }))
      .catch(() => setState({ kind: "offline" }));
  }, []);
  const text = state.kind === "live" ? state.line : state.kind === "loading" ? "…" : "Your line here";
  return (
    <figure className="stage">
      <div className="board">{text}</div>
      <Sprite row={6} frames={6} scale={1.75} />
      <figcaption className="mono">
        {state.kind === "live" ? "Live now on 0G Galileo" : state.kind === "offline" ? "Live line unavailable" : state.kind === "none" ? "No campaign live" : " "}
      </figcaption>
    </figure>
  );
}
