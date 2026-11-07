"use client";

import { useEffect, useState } from "react";
import { activeCampaign } from "@/lib/api";
import { HookTicker } from "./HookTicker";

const EXAMPLES = ["Still grepping logs at 2am? There's a pet for that.", "Your agent is thinking. Your pet is earning.", "Ship it before the coffee cools."];

/** The pet strolling across the hero with the live campaign's hooks, or clearly labelled examples. */
export function LiveHero() {
  const [live, setLive] = useState<string[] | null>(null);
  useEffect(() => {
    activeCampaign().then((c) => setLive(c?.hooks?.length ? c.hooks : null)).catch(() => setLive(null));
  }, []);
  return (
    <div className="stroll">
      <HookTicker hooks={live ?? EXAMPLES} scale={1.5} label={live ? "Live now on 0G Galileo" : "Example hooks"} />
    </div>
  );
}
