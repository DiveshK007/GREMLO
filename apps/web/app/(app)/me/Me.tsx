"use client";

import { useEffect, useState } from "react";
import { getPet, type PetPublic } from "@/lib/api";
import { PetSmall } from "@/components/PetArt";
import { addressLink, formatNear, formatWhen, PRODUCT, txLink } from "@/lib/config";

const KEY = "notchi.pet";
const near = (yocto: string | null) => (yocto === null ? "unknown" : formatNear(BigInt(yocto)));

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
    const text = `My ${PRODUCT} pet ${pet.name} earned ${near(pet.week.wei)} this week from ${pet.week.views} verified views while my coding agent worked.${pet.level ? ` Level ${pet.level}` : ""}${pet.streak ? `, ${pet.streak}-day streak` : ""}.`;
    const url = `${window.location.origin}/me?pet=${encodeURIComponent(pet.name)}`;
    return `https://x.com/intent/post?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`;
  })();

  return (
    <div className="narrow">
      <p className="mono section-kicker">Your pet</p>
      <h1>{pet ? pet.name : "How is your pet doing?"}</h1>
      <form className="topup" onSubmit={(e) => { e.preventDefault(); if (name.trim()) void load(name.trim()); }}>
        <label htmlFor="pet">Pet name</label>
        <input id="pet" value={name} onChange={(e) => setName(e.target.value)} placeholder="mochi" autoComplete="off" />
        <button type="submit" disabled={busy || !name.trim()}>{busy ? "Loading…" : "Show"}</button>
      </form>
      {error && <p className="bad" role="alert">{error}</p>}
      {pet && (
        <div className="card">
          <PetSmall />
          {pet.seeded && <p className="bad">Seeded data on a local sandbox, not real money.</p>}
          <dl className="receipt">
            <div><dt>This week</dt><dd>{near(pet.week.wei)} for {pet.week.views} views</dd></div>
            <div><dt>Paid by brands, all time</dt><dd>{pet.paidViews === null ? "chain unreachable" : `${near(pet.earnedWei)} for ${pet.paidViews} views`}</dd></div>
            <div><dt>Level</dt><dd>{pet.level ?? "unknown"}</dd></div>
            <div><dt>Streak</dt><dd>{pet.streak ? `${pet.streak} day${pet.streak === 1 ? "" : "s"}` : "starts with your next session"}</dd></div>
            <div><dt>Views today</dt><dd>{pet.impressionsToday}</dd></div>
            <div><dt>Mood</dt><dd>{pet.mood}{pet.moodReason ? `: ${pet.moodReason}` : ""}</dd></div>
          </dl>
          <p className="muted">Earnings come from settlements in the <a href={addressLink(pet.vault)} target="_blank" rel="noreferrer">vault</a>, paid to <a className="mono" href={addressLink(pet.payout)} target="_blank" rel="noreferrer">{pet.payout}</a>. The streak and level are just for fun and never change what you're paid.</p>
          {share && <a className="button ghost" href={share} target="_blank" rel="noreferrer">Share this week on X</a>}
        </div>
      )}
      {pet && (
        <div className="card">
          <h2>Compute budget</h2>
          <p className="muted">A share of every settlement ({pet.compute ? pet.compute.shareBps / 100 : "?"}%) stays in the vault as the pet&apos;s compute budget. Each AI call is charged a fixed per-tier rate in NEAR, not the real USD bill from NEAR AI, with the call&apos;s completion id in the onchain log.</p>
          {pet.compute ? (
            <dl className="receipt">
              <div><dt>Budget left</dt><dd>{near(pet.compute.budget)}</dd></div>
              <div><dt>Spent on AI, all time</dt><dd>{near(pet.compute.spent)}</dd></div>
              <div><dt>Charged today</dt><dd>{near(pet.compute.chargedToday)} of {near(pet.compute.dailyCap)} a day</dd></div>
              <div><dt>Rate per call</dt><dd>{near(pet.compute.feeSmart)} smart · {near(pet.compute.feeCheap)} cheap</dd></div>
            </dl>
          ) : <p className="bad">Can&apos;t read the vault right now.</p>}
          {pet.lastThoughts.length > 0 && (
            <table className="hooks-table">
              <thead><tr><th>When</th><th>Action</th><th>Model</th><th>Completion id</th><th>Charge</th></tr></thead>
              <tbody>
                {pet.lastThoughts.map((t) => (
                  <tr key={t.requestId + t.at}>
                    <td>{formatWhen(t.at * 1000)}</td>
                    <td>{t.action}</td>
                    <td className="mono">{t.model ?? "–"}</td>
                    <td className="mono">{t.requestId}</td>
                    <td>{t.chargeTx ? <a className="mono" href={txLink(t.chargeTx)} target="_blank" rel="noreferrer">{t.chargeTx.slice(0, 8)}…</a> : "–"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </div>
  );
}
