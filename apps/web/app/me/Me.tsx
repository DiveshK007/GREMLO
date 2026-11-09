"use client";

import { useEffect, useState } from "react";
import { formatEther } from "viem";
import { getPet, type PetPublic } from "@/lib/api";
import { PetSmall } from "@/components/PetArt";

const KEY = "notchi.pet";
const og = (wei: string | null) => (wei === null ? "unknown" : `${Number(formatEther(BigInt(wei))).toFixed(4)} 0G`);

export default function Me() {
  const [name, setName] = useState("");
  const [pet, setPet] = useState<PetPublic | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function load(n: string) {
    setError("");
    setBusy(true);
    try {
      const p = await getPet(n);
      setPet(p);
      try { localStorage.setItem(KEY, n); } catch {}
      window.history.replaceState(null, "", `/me?pet=${encodeURIComponent(n)}`);
    } catch (e) {
      setPet(null);
      setError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    let n = new URLSearchParams(window.location.search).get("pet") ?? "";
    if (!n) try { n = localStorage.getItem(KEY) ?? ""; } catch {}
    if (n) { setName(n); void load(n); }
  }, []);

  const share = pet && (() => {
    const text = `My Notchi pet ${pet.name} earned ${og(pet.week.wei)} this week from ${pet.week.views} verified views while my coding agent worked.${pet.level ? ` Level ${pet.level}` : ""}${pet.streak ? `, ${pet.streak}-day streak` : ""}.`;
    const url = `${window.location.origin}/me?pet=${encodeURIComponent(pet.name)}`;
    return `https://x.com/intent/post?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`;
  })();

  return (
    <div className="narrow">
      <p className="mono section-kicker">Your pet</p>
      <h1>{pet ? pet.name : "How is your pet doing?"}</h1>
      <form className="topup" onSubmit={(e) => { e.preventDefault(); if (name.trim()) void load(name.trim()); }}>
        <label htmlFor="pet">Pet name</label>
        <input id="pet" value={name} onChange={(e) => setName(e.target.value)} placeholder="mochi.notchi.eth" autoComplete="off" />
        <button type="submit" disabled={busy || !name.trim()}>{busy ? "Loading…" : "Show"}</button>
      </form>
      {error && <p className="bad" role="alert">{error}</p>}
      {pet && (
        <div className="card">
          <PetSmall />
          {pet.seeded && <p className="bad">Seeded data on a local chain, not real 0G.</p>}
          <dl className="receipt">
            <div><dt>This week</dt><dd>{og(pet.week.wei)} for {pet.week.views} views</dd></div>
            <div><dt>Paid by brands, all time</dt><dd>{pet.paidViews === null ? "chain unreachable" : `${og(pet.earnedWei)} for ${pet.paidViews} views`}</dd></div>
            <div><dt>Level</dt><dd>{pet.level ?? "unknown"}</dd></div>
            <div><dt>Streak</dt><dd>{pet.streak ? `${pet.streak} day${pet.streak === 1 ? "" : "s"}` : "starts with your next session"}</dd></div>
            <div><dt>Views today</dt><dd>{pet.impressionsToday}</dd></div>
            <div><dt>Mood</dt><dd>{pet.mood}{pet.moodReason ? `: ${pet.moodReason}` : ""}</dd></div>
          </dl>
          <p className="muted">Earnings come from settlements on the 0G chain. The streak and level are just for fun and never change what you're paid.</p>
          {share && <a className="button ghost" href={share} target="_blank" rel="noreferrer">Share this week on X</a>}
        </div>
      )}
    </div>
  );
}
