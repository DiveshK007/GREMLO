"use client";

import { useEffect, useState } from "react";
import {
  ApiError, arkivCampaign, campaignStats, checkCampaign, FORMATS, type ArkivView, recordCampaign, settleImpressions, suggestHooks,
  type Brief, type Dropped, type Hook, type Settlement, type Stats,
} from "@/lib/api";
import { closeCampaign, connectWallet, createCampaign, lineHash, readCampaign, topUpCampaign } from "@/lib/chain";
import { addressLink, formatNear, formatWhen, parseNear, SERVER_URL, txLink, VAULT_ID } from "@/lib/config";
import { PetSmall } from "@/components/PetArt";
import { HookTicker } from "@/components/HookTicker";

/** Seconds since mount, so a long AI call visibly moves. */
function Elapsed() {
  const [s, setS] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setS((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  return <>{s}s</>;
}

const MIN_HOOK = 6, MAX_HOOK = 40; // the plate shows a line whole, never truncated or scrolled
const MIN_PICK = 1, MAX_PICK = 4; // up to 4 lines per campaign for the A/B test
const FORMAT_LABEL: Record<string, string> = {
  humour: "Humour", sarcasm: "Sarcasm", offer: "Irresistible offer", question: "Question", "bold-claim": "Bold claim",
  urgency: "Urgency", story: "Mini story", "dev-meme": "Dev meme", own: "Your own",
};

type Funded = { campaignId: bigint; txHash: string; hooks: string[]; budgetWei: bigint; rateWei: bigint; endTime: bigint; recordWarning?: string };
type Lookup = Awaited<ReturnType<typeof readCampaign>>;

const emptyBrief: Brief = { product: "", audience: "", offer: "", proof: "", cta: "" };

export default function FundCampaign() {
  const [account, setAccount] = useState<string | null>(null);
  const [brief, setBrief] = useState<Brief>(emptyBrief);
  const [url, setUrl] = useState("");
  const [attest, setAttest] = useState(false);
  const [email, setEmail] = useState("");
  const [hooks, setHooks] = useState<Hook[]>([]);
  const [dropped, setDropped] = useState<Dropped[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [moments, setMoments] = useState<Record<string, string>>({}); // line -> tests | deploy | long run | any
  const [own, setOwn] = useState("");
  const [budget, setBudget] = useState("0.1");
  const [rate, setRate] = useState("0.001");
  const [hours, setHours] = useState("24");
  const [endsAt, setEndsAt] = useState(""); // formatted in the browser only (hydration)
  useEffect(() => {
    const h = Number(hours);
    setEndsAt(h > 0 ? formatWhen(Date.now() + h * 3_600_000) : "");
  }, [hours]);
  const [walletError, setWalletError] = useState("");
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [hooksError, setHooksError] = useState("");
  const [campaignError, setCampaignError] = useState("");
  const [funded, setFunded] = useState<Funded | null>(null);

  const [lookupId, setLookupId] = useState("");
  const [lookup, setLookup] = useState<Lookup | null>(null);
  const [stats, setStats] = useState<Stats | null>(null);
  const [arkiv, setArkiv] = useState<ArkivView | null>(null);
  const [refund, setRefund] = useState<{ txHash: string; amount: bigint } | null>(null);
  const [topUp, setTopUp] = useState("0.5");
  const [toppedUp, setToppedUp] = useState<{ txHash: string; amount: string } | null>(null);
  const [settlement, setSettlement] = useState<Settlement | null>(null);
  const [copied, setCopied] = useState(false);

  const setField = (k: keyof Brief) => (e: { target: { value: string } }) => setBrief((b) => ({ ...b, [k]: e.target.value }));
  const toggle = (text: string) =>
    setPicked((p) => (p.includes(text) ? p.filter((t) => t !== text) : p.length >= MAX_PICK ? p : [...p, text]));

  // a share link like /brand?c=12 opens straight on that campaign's dashboard
  useEffect(() => {
    const c = new URLSearchParams(window.location.search).get("c");
    if (c && /^\d+$/.test(c)) { setLookupId(c); void loadCampaign(c); }
  }, []);

  async function onConnect() {
    setWalletError("");
    try {
      setAccount(await connectWallet());
    } catch (e) {
      setWalletError((e as Error).message);
    }
  }

  function briefProblem() {
    if (!brief.product.trim()) return "Say what your product is.";
    if (!brief.audience.trim()) return "Say who it's for.";
    if (!brief.cta.trim()) return "Add a call to action, like \"Try it free\".";
    if (!/^https:\/\/[^\s]+\.[^\s]+/.test(url.trim())) return "Add your https link; clicking the pet's sign opens it.";
    if (!attest) return "Confirm the proof points are your own, accurate claims.";
    return "";
  }

  async function onHooks() {
    setHooksError("");
    const problem = briefProblem();
    if (problem) return setHooksError(problem);
    setBusy("hooks");
    try {
      const res = await suggestHooks(brief, url.trim());
      setHooks(res.hooks);
      setDropped(res.dropped);
      setPicked(res.hooks.slice(0, MIN_PICK).map((h) => h.text));
    } catch (e) {
      setHooks([]);
      setDropped([]);
      const msg = (e as Error).message;
      setHooksError(e instanceof ApiError && e.status === 400 ? msg : `Couldn't write hooks: ${msg}. Try again, or write your own below.`);
    } finally {
      setBusy("");
    }
  }

  function onAddOwn() {
    const t = own.trim();
    if (!t) return;
    if (t.length < MIN_HOOK || t.length > MAX_HOOK) return setHooksError(`A line is ${MIN_HOOK} to ${MAX_HOOK} characters.`);
    if (hooks.some((h) => h.text === t)) return setHooksError("That hook is already in the list.");
    setHooksError("");
    setHooks((h) => [...h, { format: "own", text: t }]);
    setPicked((p) => (p.length >= MAX_PICK ? p : [...p, t]));
    setOwn("");
  }

  async function onFund() {
    setError("");
    if (!account) return setError("Connect your wallet first.");
    const problem = briefProblem();
    if (problem) return setError(problem);
    if (picked.length < MIN_PICK || picked.length > MAX_PICK) return setError(`Pick ${MIN_PICK} to ${MAX_PICK} hooks for the pet to rotate.`);
    let budgetWei: bigint, rateWei: bigint;
    try {
      budgetWei = parseNear(budget);
      rateWei = parseNear(rate);
    } catch {
      return setError("Budget and price must be numbers.");
    }
    const h = Number(hours);
    if (!(rateWei > 0n)) return setError("Price per view must be more than 0.");
    if (budgetWei < rateWei) return setError("Budget must cover at least one view.");
    if (!(h > 0)) return setError("Duration must be more than 0 hours.");

    setBusy("check");
    try {
      await checkCampaign(brief, picked, url.trim(), email.trim()); // refuse here, before any money moves
    } catch (e) {
      setBusy("");
      return setError((e as Error).message);
    }
    setBusy("fund");
    try {
      const line = picked.join("\n");
      const endTime = BigInt(Math.floor(Date.now() / 1000 + h * 3600));
      const { txHash, campaignId } = await createCampaign({ account, line, budgetWei, rateWei, endTime });
      let recordWarning: string | undefined;
      setBusy("record");
      try {
        await recordCampaign({ campaignId: campaignId.toString(), hooks: picked, moments: picked.map((h) => moments[h] ?? "any"), lineHash: lineHash(line), brand: account, txHash, url: url.trim(), brief, email: email.trim() || undefined });
      } catch (e) {
        recordWarning = `Paid onchain, but the server didn't save your hooks: ${(e as Error).message}. Your budget is safe; contact us with the receipt.`;
      }
      setFunded({ campaignId, txHash, hooks: picked, budgetWei, rateWei, endTime, recordWarning });
      setLookupId(campaignId.toString());
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (e) {
      setError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function loadCampaign(id: string) {
    setCampaignError("");
    setRefund(null);
    setToppedUp(null);
    if (!/^\d+$/.test(id)) return setCampaignError("Enter a campaign ID number, like 2.");
    setBusy("lookup");
    try {
      const [l, s, a] = await Promise.all([readCampaign(BigInt(id)), campaignStats(id).catch(() => null), arkivCampaign(id).catch(() => null)]);
      setLookup(l);
      setStats(s);
      setArkiv(a);
    } catch (e) {
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function onSettle() {
    setCampaignError("");
    setSettlement(null);
    if (!/^\d+$/.test(lookupId)) return setCampaignError("Enter a campaign ID number, like 2.");
    setBusy("settle");
    try {
      setSettlement(await settleImpressions(lookupId));
      setLookup(await readCampaign(BigInt(lookupId)));
    } catch (e) {
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function onClose() {
    setCampaignError("");
    if (!account) return setCampaignError("Connect your wallet first.");
    setBusy("close");
    try {
      const res = await closeCampaign(account, BigInt(lookupId));
      setRefund({ txHash: res.txHash, amount: res.refund });
      setLookup(await readCampaign(BigInt(lookupId)));
    } catch (e) {
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function onTopUp(e: React.FormEvent) {
    e.preventDefault();
    setCampaignError("");
    setToppedUp(null);
    if (!account) return setCampaignError("Connect the wallet that created this campaign first.");
    let wei: bigint;
    try {
      wei = parseNear(topUp);
    } catch {
      return setCampaignError("Enter an amount in NEAR, like 0.5.");
    }
    if (wei <= 0n) return setCampaignError("Enter an amount in NEAR, like 0.5.");
    setBusy("topup");
    try {
      const txHash = await topUpCampaign(account, BigInt(lookupId), wei);
      setToppedUp({ txHash, amount: topUp });
      setLookup(await readCampaign(BigInt(lookupId)));
    } catch (e) {
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  function onShare() {
    if (!funded) return;
    void navigator.clipboard?.writeText(`${window.location.origin}/brand?c=${funded.campaignId}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  const nowSec = BigInt(Math.floor(Date.now() / 1000));
  const usedPct = lookup && lookup.budget > 0n ? Number((lookup.spent * 100n) / lookup.budget) : 0; // integer math on wei
  const estimate = (() => {
    try {
      const r = parseNear(rate);
      return r > 0n ? (parseNear(budget) / r).toString() : "–";
    } catch {
      return "–";
    }
  })();
  const fundLabel = busy === "check" ? "Checking your hooks…" : busy === "fund" ? "Confirm in your wallet…" : busy === "record" ? "Saving your hooks…" : "Fund campaign";
  const groups = [...FORMATS, "own" as const].map((f) => ({ f, list: hooks.filter((h) => h.format === f) })).filter((g) => g.list.length);

  if (funded) {
    return (
      <div className="narrow live">
        <p className="mono live-tag">Campaign #{funded.campaignId.toString()} · live on NEAR testnet</p>
        <h1>Your campaign is live.</h1>
        <p className="lead">Developers will see your hooks the next time their coding agent starts working. The pet rotates them and shifts toward whichever gets clicked.</p>
        <HookTicker hooks={funded.hooks} scale={1.6} label="Preview: what developers see" />
        <dl className="receipt">
          <div><dt>Budget</dt><dd>{formatNear(funded.budgetWei)} NEAR</dd></div>
          <div><dt>Price per view</dt><dd>{formatNear(funded.rateWei)} NEAR</dd></div>
          <div><dt>Estimated views</dt><dd>{(funded.budgetWei / funded.rateWei).toString()} <span className="muted">(estimate)</span></dd></div>
          <div><dt>Ends</dt><dd>{formatWhen(Number(funded.endTime) * 1000)} <span className="muted">(views paid until 1 hour later, then the rest is refunded)</span></dd></div>
          <div><dt>Receipt</dt><dd><a className="mono" href={txLink(funded.txHash)} target="_blank" rel="noreferrer">{funded.txHash.slice(0, 10)}…{funded.txHash.slice(-6)}</a></dd></div>
        </dl>
        {funded.recordWarning && <p className="bad">{funded.recordWarning}</p>}
        <p className="actions">
          <button onClick={() => { setFunded(null); void loadCampaign(funded.campaignId.toString()); setTimeout(() => document.getElementById("dashboard")?.scrollIntoView({ behavior: "smooth" }), 50); }}>
            View dashboard
          </button>
          <button className="ghost" onClick={onShare}>{copied ? "Link copied" : "Copy share link"}</button>
          <button className="ghost" onClick={() => { setFunded(null); setHooks([]); setPicked([]); setDropped([]); }}>Start another</button>
        </p>
      </div>
    );
  }

  return (
    <div className="narrow">
      <h1>Fund a campaign</h1>
      <p className="lead">Your hook, carried across a developer's screen by a tiny pet while their AI agent works. Pay per real, verified view.</p>

      {!account ? (
        <>
          <button onClick={onConnect}>Connect NEAR wallet</button>
          {walletError && <p className="bad">{walletError}</p>}
        </>
      ) : (
        <p className="muted">Paying from <span className="mono">{account}</span></p>
      )}

      <div className="card">
        <h2><span className="mono num">01</span>Your product</h2>
        <label htmlFor="product">What is it?</label>
        <input id="product" value={brief.product} onChange={setField("product")} maxLength={160} placeholder="Clearlog, log search for TypeScript teams" />
        <label htmlFor="audience">Who is it for?</label>
        <input id="audience" value={brief.audience} onChange={setField("audience")} maxLength={120} placeholder="backend developers" />
        <label htmlFor="offer">Offer (optional)</label>
        <input id="offer" value={brief.offer} onChange={setField("offer")} maxLength={120} placeholder="first 1M logs free" />
        <label htmlFor="proof">Proof points (optional, one per line)</label>
        <textarea id="proof" value={brief.proof} onChange={setField("proof")} maxLength={600} placeholder={"Indexes 1M logs in 30 seconds\nUsed by 40 teams"} />
        <p className="hint">Hooks may only use numbers and claims from here. Promises of returns or profit are never allowed.</p>
        <div className="row">
          <div>
            <label htmlFor="cta">Call to action</label>
            <input id="cta" value={brief.cta} onChange={setField("cta")} maxLength={40} placeholder="Try it free" />
          </div>
          <div>
            <label htmlFor="url">Link</label>
            <input id="url" value={url} onChange={(e) => setUrl(e.target.value)} maxLength={300} placeholder="https://clearlog.dev" />
          </div>
        </div>
        <label className="check">
          <input type="checkbox" checked={attest} onChange={(e) => setAttest(e.target.checked)} />
          <span>These proof points are our own claims, and they're accurate.</span>
        </label>
        <p>
          <button onClick={onHooks} disabled={busy === "hooks"} aria-busy={busy === "hooks"}>
            {busy === "hooks" ? "Writing hooks…" : hooks.length ? "Write new hooks" : "Write my hooks"}
          </button>
        </p>
        {busy === "hooks" && (
          <div className="thinking" role="status">
            <PetSmall />
            <div>
              <strong>Writing 16 hooks on NEAR AI Cloud…</strong>
              <span className="muted">Then every hook is checked against your proof points. This can take up to two minutes. <Elapsed /></span>
            </div>
          </div>
        )}
        {hooksError && <p className="bad" role="alert">{hooksError}</p>}
      </div>

      {(hooks.length > 0 || hooksError) && (
        <div className="card">
          <h2><span className="mono num">02</span>Pick {MIN_PICK} to {MAX_PICK} hooks</h2>
          <p className="muted">Picked {picked.length} of {MAX_PICK}. Traffic is even until each line has 2,000 sightings, then favours the lines developers open.</p>
          {picked.length > 0 && (
            <div className="moments">
              <p className="muted">When should each line show? The pet works out the moment on the developer&apos;s Mac; nothing about their work is sent.</p>
              {picked.map((h) => (
                <label key={h} className="moment">
                  <span>{h}</span>
                  <select value={moments[h] ?? "any"} onChange={(e) => setMoments({ ...moments, [h]: e.target.value })}>
                    <option value="any">any time</option>
                    <option value="tests">while tests run</option>
                    <option value="deploy">during a deploy</option>
                    <option value="long run">on a long run</option>
                  </select>
                </label>
              ))}
            </div>
          )}
          {groups.map(({ f, list }) => (
            <div key={f} className="hook-group">
              <p className="mono hook-format">{FORMAT_LABEL[f]}</p>
              {list.map((h) => {
                const on = picked.includes(h.text);
                return (
                  <button key={h.text} className={`sign ${on ? "picked" : ""}`} aria-pressed={on} onClick={() => toggle(h.text)} disabled={!on && picked.length >= MAX_PICK}>
                    {h.text}
                    <small>
                      <span className="mono">{h.requestId ? `written by AI · ${h.requestId}` : "written by you"}</span>
                      <span className="mono count">{h.text.length}/{MAX_HOOK}</span>
                    </small>
                  </button>
                );
              })}
            </div>
          ))}
          {dropped.length > 0 && (
            <details className="dropped">
              <summary>{dropped.length} hook{dropped.length === 1 ? "" : "s"} didn't pass the claim checks</summary>
              <ul>{dropped.map((d, i) => <li key={i}><span>{d.text}</span> <span className="muted">— {d.reason}</span></li>)}</ul>
            </details>
          )}
          <label htmlFor="own">Write your own</label>
          <div className="own-row">
            <input id="own" value={own} onChange={(e) => setOwn(e.target.value)} maxLength={MAX_HOOK} placeholder="Logs, found. Try Clearlog free" onKeyDown={(e) => e.key === "Enter" && onAddOwn()} />
            <button className="ghost" onClick={onAddOwn} disabled={!own.trim()}>Add</button>
          </div>
          <p className="hint mono count">{own.trim().length}/{MAX_HOOK}</p>
        </div>
      )}

      <div className="card">
        <h2><span className="mono num">{hooks.length ? "03" : "02"}</span>Budget</h2>
        <div className="row">
          <div>
            <label htmlFor="budget">Total budget (NEAR)</label>
            <input id="budget" value={budget} onChange={(e) => setBudget(e.target.value)} />
          </div>
          <div>
            <label htmlFor="rate">Price per view (NEAR)</label>
            <input id="rate" value={rate} onChange={(e) => setRate(e.target.value)} />
          </div>
          <div>
            <label htmlFor="hours">Runs for (hours)</label>
            <input id="hours" value={hours} onChange={(e) => setHours(e.target.value)} aria-describedby="ends-at" />
            <p className="hint" id="ends-at">{Number(hours) > 0 ? `Ends ${endsAt || "…"}. Views can still be paid for 1 hour after that; then the unspent budget is refunded.` : "Enter the hours it should run."}</p>
          </div>
        </div>
        <label htmlFor="email">Email for budget alerts and a weekly report (optional)</label>
        <input id="email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} maxLength={254} placeholder="you@company.com" />
        <p className="muted">Only used to email you about this campaign. Never shown or shared.</p>
        <div className="summary">
          <span className="estimate">{estimate}</span>
          <p>views, roughly, at this price. Any unspent budget is refunded when the campaign ends.</p>
          {error && <p className="bad" role="alert">{error}</p>}
          <button onClick={onFund} disabled={!account || !!busy || picked.length < MIN_PICK}>{fundLabel}</button>
          {!account && <p className="hint">Connect your wallet at the top to fund.</p>}
          {account && picked.length < MIN_PICK && <p className="hint">Pick at least {MIN_PICK} hooks first.</p>}
          <p className="muted">
            Contract:{" "}
            <a className="mono" href={addressLink(VAULT_ID)} target="_blank" rel="noreferrer">{VAULT_ID}</a>
          </p>
        </div>
      </div>

      <div className="card" id="dashboard">
        <h2><span className="mono num">{hooks.length ? "04" : "03"}</span>Your campaign</h2>
        <div className="row">
          <div>
            <label htmlFor="cid">Campaign ID</label>
            <input id="cid" value={lookupId} onChange={(e) => setLookupId(e.target.value)} placeholder="1" />
            <p className="hint">Shown after you fund, as Campaign #N.</p>
          </div>
        </div>
        <p>
          <button className="ghost" onClick={() => loadCampaign(lookupId)} disabled={busy === "lookup"}>{busy === "lookup" ? "Checking…" : "Check"}</button>{" "}
          <button className="ghost" onClick={onSettle} disabled={busy === "settle"}>{busy === "settle" ? "Settling onchain…" : "Settle views"}</button>
        </p>
        {campaignError && <p className="bad" role="alert">{campaignError}</p>}
        {settlement && (
          <>
            {settlement.count === 0 && !settlement.error && <p className="muted">No views queued for this campaign yet.</p>}
            {settlement.count > 0 && (
              <p className="ok">
                Paid {settlement.count} view{settlement.count === 1 ? "" : "s"}, {formatNear(BigInt(settlement.amount))} NEAR
                {settlement.seeded ? " [seeded, local sandbox]" : ""}
              </p>
            )}
            {settlement.settled.map((s) => (
              <p key={s.txHash} className="muted">
                {s.count} to pet <span className="mono">{s.petKey}</span>:{" "}
                <a className="mono" href={txLink(s.txHash)} target="_blank" rel="noreferrer">{s.txHash}</a>
              </p>
            ))}
            {settlement.error && <p className="bad">Settlement stopped: {settlement.error}</p>}
          </>
        )}
        {lookup && (
          <>
            <p>
              Budget {formatNear(lookup.budget)} NEAR · spent {formatNear(lookup.spent)} NEAR · left {formatNear(lookup.remaining)} NEAR
            </p>
            <div className="budget-meter" role="meter" aria-label="Budget spent" aria-valuemin={0} aria-valuemax={100} aria-valuenow={usedPct}>
              <span style={{ width: `${Math.min(usedPct, 100)}%` }} data-level={usedPct >= 80 ? "high" : usedPct >= 50 ? "half" : undefined} />
            </div>
            {!lookup.closed && usedPct >= 50 && (
              <p className={usedPct >= 80 ? "bad" : "muted"} role="status">
                {usedPct >= 100 ? "Budget used up: your hooks have stopped showing." : `${usedPct}% of the budget is spent.`}
                {lookup.endTime > nowSec ? " Top up below to keep them running." : ""}
              </p>
            )}
            {!lookup.closed && lookup.endTime > nowSec && (
              <form className="topup" onSubmit={onTopUp}>
                <label htmlFor="topup">Add budget (NEAR)</label>
                <input id="topup" inputMode="decimal" value={topUp} onChange={(e) => setTopUp(e.target.value)} />
                <button type="submit" disabled={busy === "topup"}>{busy === "topup" ? "Topping up…" : "Top up"}</button>
              </form>
            )}
            {toppedUp && (
              <p className="ok">
                Added {toppedUp.amount} NEAR:{" "}
                <a className="mono" href={txLink(toppedUp.txHash)} target="_blank" rel="noreferrer">{toppedUp.txHash}</a>
              </p>
            )}
            <p className="muted">
              {lookup.closed
                ? "Closed. Unspent budget was refunded."
                : lookup.endTime > nowSec
                  ? `Running until ${formatWhen(Number(lookup.endTime) * 1000)}.`
                  : lookup.endTime + 3600n > nowSec
                    ? `Ended. Views can be settled until ${formatWhen(Number(lookup.endTime + 3600n) * 1000)}; then it can be closed and refunded.`
                    : "Ended and the settlement window has passed. Close it to refund what's left."}
            </p>
            {stats && (
              <table className="stats-table">
                <thead><tr><th>Hook</th><th>Views</th><th>Clicks</th><th>Click rate</th></tr></thead>
                <tbody>
                  {stats.views.map((v, i) => (v || stats.clicks[i] ? (
                    <tr key={i}><td>#{i + 1}</td><td>{v}</td><td>{stats.clicks[i]}</td><td>{v ? `${((stats.clicks[i] / v) * 100).toFixed(1)}%` : "–"}</td></tr>
                  ) : null))}
                  {stats.views.every((v, i) => !v && !stats.clicks[i]) && <tr><td colSpan={4} className="muted">No views yet. They appear here as developers' agents start working.</td></tr>}
                </tbody>
              </table>
            )}
            {arkiv?.on && (
              <div className="arkiv">
                <p className="mono section-kicker">Mirrored on Arkiv</p>
                {arkiv.card ? (
                  <p>
                    Campaign card <span className="mono">{arkiv.card.key.slice(0, 10)}…</span>, expires at Arkiv block {arkiv.card.expiresAt}.{" "}
                    {arkiv.receipts.length} settlement receipt{arkiv.receipts.length === 1 ? "" : "s"}.{" "}
                    <a href={arkiv.explorer} target="_blank" rel="noreferrer">Arkiv explorer</a>
                  </p>
                ) : (
                  <p className="muted">Not on Arkiv yet. It's published when the campaign is saved.</p>
                )}
              </div>
            )}
            {stats?.best != null && (
              <p>Best hook so far: #{stats.best + 1}, {((stats.clicks[stats.best] / stats.views[stats.best]) * 100).toFixed(1)}% of views clicked.</p>
            )}
            {stats?.emailAlerts && <p className="muted">Budget alerts and the weekly report go to the email you gave.</p>}
            {stats && stats.heldViews > 0 && (
              <p className="muted">{stats.heldViews} view{stats.heldViews === 1 ? "" : "s"} in the fraud check{stats.holdbackHours ? ` (paid after ${stats.holdbackHours}h)` : ""}.</p>
            )}
            {stats && Object.entries(stats.voided).map(([reason, n]) => (
              <p key={reason} className="muted">{n} view{n === 1 ? "" : "s"} voided, not charged: {reason}.</p>
            ))}
            {stats && stats.pendingViews > 0 && <p className="muted">{stats.pendingViews} view{stats.pendingViews === 1 ? "" : "s"} waiting to be settled.</p>}
            {stats?.moments && Object.keys(stats.moments).length > 0 && (
              <p className="muted">By moment: {Object.entries(stats.moments).map(([m, n]) => `${m} ${n ?? "(under 50 pets)"}`).join(" · ")}</p>
            )}
            {stats?.paused && stats.paused.length > 0 && <p className="muted">Paused by reports: line {stats.paused.map((i) => i + 1).join(", ")}.</p>}
            {stats && (
              <p className="muted">
                Every counted view is a signed report from a pet. <a href={`${SERVER_URL}/campaigns/${stats.campaignId}/log`}>Public log</a> · check it yourself with <code>notchi verify {stats.campaignId}</code>
              </p>
            )}
            {!lookup.closed && lookup.endTime + 3600n <= nowSec && (
              <button onClick={onClose} disabled={busy === "close"}>{busy === "close" ? "Closing…" : "Close and refund"}</button>
            )}
          </>
        )}
        {refund && (
          <p className="ok">
            Refunded {formatNear(refund.amount)} NEAR:{" "}
            <a className="mono" href={txLink(refund.txHash)} target="_blank" rel="noreferrer">{refund.txHash}</a>
          </p>
        )}
      </div>
    </div>
  );
}
