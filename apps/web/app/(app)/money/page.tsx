"use client";

import { useEffect, useState } from "react";
import { formatNear, SERVER_URL } from "@/lib/config";

type Stats = { campaigns: number; settledViews: string; paidWei: string; computeChargedWei: string; pets: number; seeded: boolean };

// R2 §16: where a brand's money goes, with the live totals read from the vault. A dash means unknown.
export default function Money() {
  const [s, setS] = useState<Stats | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    fetch(`${SERVER_URL}/stats`).then((r) => r.json()).then(setS).catch(() => setError("Can't read the totals right now."));
  }, []);
  const n = (v?: string) => (v ? formatNear(BigInt(v)) : "—");
  return (
    <main>
      <h1>Where the money goes</h1>
      {s?.seeded && <p className="mono">SEEDED DATA: not real</p>}
      <ol className="money">
        <li><strong>A brand pays</strong> per 1,000 sightings, up front, into the campaign.</li>
        <li><strong>The platform fee</strong> is <span className="mono">{"—"}</span> until the rate is published.</li>
        <li><strong>The rest goes to the pet&apos;s balance</strong>, one settlement per pet, each with a receipt.</li>
        <li><strong>Meals come first:</strong> part of each settlement feeds the pet&apos;s own compute budget, which pays for its thinking.</li>
        <li><strong>Surplus</strong> above a small reserve goes to the owner&apos;s payout account.</li>
        <li><strong>Unspent budget</strong> goes back to the brand when the campaign closes.</li>
      </ol>
      <section className="card">
        <h2>So far</h2>
        {error && <p className="error">{error}</p>}
        <p>Campaigns <span className="mono">{s?.campaigns ?? "—"}</span> · pets <span className="mono">{s?.pets ?? "—"}</span> · settled sightings <span className="mono">{s?.settledViews ?? "—"}</span></p>
        <p>Paid to pets <span className="mono">{n(s?.paidWei)}</span> · paid for thinking <span className="mono">{n(s?.computeChargedWei)}</span></p>
      </section>
      <section className="card">
        <h2>A sighting counts only when</h2>
        <p className="muted">the plate is fully visible for 2 seconds or more, the screen is unlocked, not shared and not recorded, someone used the Mac in the last minute, and the pet is under 12 lines an hour. Every counted sighting is a signed report in the campaign&apos;s public log; <code>gremlo verify &lt;campaign&gt;</code> checks it against the bill.</p>
      </section>
    </main>
  );
}
