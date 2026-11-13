"use client";

import { useEffect, useState } from "react";
import {
  ApiError, arkivCampaign, campaignStats, checkCampaign, FORMATS, type ArkivView, recordCampaign, settleImpressions, suggestHooks,
  type Brief, type Dropped, type Hook, type Settlement, type Stats,
} from "@/lib/api";
import { closeCampaign, connectWallet, createCampaign, lineHash, readCampaign, topUpCampaign } from "@/lib/chain";
import { addressLink, formatNear, formatWhen, parseNear, SERVER_URL, txLink, VAULT_ID } from "@/lib/config";
import { Pet } from "@/components/Pet";
import { Plate } from "@/components/Plate";
import { toast, useNotch } from "@/components/Shell";
import "./brand.css";

const MIN_HOOK = 6, MAX_HOOK = 40; // the plate shows a line whole, never truncated or scrolled (R2 §2)
const MIN_PICK = 1, MAX_PICK = 4; // up to 4 lines per campaign for the A/B test (R2 §15)
const PREVIEW = "pip"; // the preview pet; brands don't pick one, every species carries lines
const FORMAT_LABEL: Record<string, string> = {
  humour: "Humour", sarcasm: "Sarcasm", offer: "Irresistible offer", question: "Question", "bold-claim": "Bold claim",
  urgency: "Urgency", story: "Mini story", "dev-meme": "Dev meme", own: "Your own",
};
const MOMENTS: [string, string][] = [["any", "any time"], ["tests", "while tests run"], ["deploy", "during a deploy"], ["long run", "on a long run"]];

type Funded = { campaignId: bigint; txHash: string; hooks: string[]; budgetWei: bigint; rateWei: bigint; endTime: bigint; recordWarning?: string };
type Lookup = Awaited<ReturnType<typeof readCampaign>>;
const emptyBrief: Brief = { product: "", audience: "", offer: "", proof: "", cta: "" };
const short = (h: string) => (h.length > 20 ? `${h.slice(0, 10)}…${h.slice(-6)}` : h);
const Tx = ({ hash, full }: { hash: string; full?: boolean }) => <a className="hash" href={txLink(hash)} target="_blank" rel="noreferrer">{full ? hash : short(hash)}</a>;

/** Seconds since mount, so a long AI call visibly moves. */
function Elapsed() {
  const [s, setS] = useState(0);
  useEffect(() => { const t = setInterval(() => setS((n) => n + 1), 1000); return () => clearInterval(t); }, []);
  return <span className="secs">{s}s</span>;
}

/** Cycles through the lines the way the pet rotates them; holds the first under reduced motion. */
function useRotate(lines: string[], every = 3200) {
  const [i, setI] = useState(0);
  useEffect(() => {
    setI(0);
    if (lines.length < 2 || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const t = setInterval(() => setI((n) => (n + 1) % lines.length), every);
    return () => clearInterval(t);
  }, [lines.join("\n"), every]); // eslint-disable-line react-hooks/exhaustive-deps
  return lines.length ? lines[i % lines.length] : null;
}

function Field({ id, label, value, onChange, max = 160, opt, ph, hint, area, suffix, bad, type }: {
  id: string; label: string; value: string; onChange: (v: string) => void; max?: number; opt?: boolean; ph?: string; hint?: string; area?: boolean; suffix?: string; bad?: boolean; type?: string;
}) {
  const props = { id, value, maxLength: max, placeholder: ph, "aria-invalid": bad || undefined, onChange: (e: { target: { value: string } }) => onChange(e.target.value) };
  const input = area ? <textarea {...props} /> : <input {...props} type={type} inputMode={suffix ? "decimal" : undefined} />;
  return (
    <div className="field" data-invalid={bad || undefined}>
      <label htmlFor={id}>{label}{opt && <> <span className="opt">(optional)</span></>}</label>
      {suffix ? <div className="suffix">{input}<span>{suffix}</span></div> : input}
      {hint && <p className="hint">{hint}</p>}
    </div>
  );
}

export default function FundCampaign() {
  const notch = useNotch();
  const [tab, setTab] = useState<"new" | "dash">("new");
  const [account, setAccount] = useState<string | null>(null);
  const [brief, setBrief] = useState<Brief>(emptyBrief);
  const [url, setUrl] = useState("");
  const [attest, setAttest] = useState(false);
  const [email, setEmail] = useState("");
  const [hooks, setHooks] = useState<Hook[]>([]);
  const [dropped, setDropped] = useState<Dropped[]>([]);
  const [picked, setPicked] = useState<string[]>([]);
  const [moments, setMoments] = useState<Record<string, string>>({});
  const [filter, setFilter] = useState("all");
  const [own, setOwn] = useState("");
  const [budget, setBudget] = useState("0.1");
  const [rate, setRate] = useState("0.001");
  const [hours, setHours] = useState("24");
  const [endsAt, setEndsAt] = useState(""); // formatted in the browser only (hydration)
  useEffect(() => { const h = Number(hours); setEndsAt(h > 0 ? formatWhen(Date.now() + h * 3_600_000) : ""); }, [hours]);
  const [walletError, setWalletError] = useState("");
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [hooksError, setHooksError] = useState("");
  const [funded, setFunded] = useState<Funded | null>(null);

  const [lookupId, setLookupId] = useState("");
  const [lookup, setLookup] = useState<Lookup | null>(null);
  const [stats, setStats] = useState<Stats | null | undefined>(undefined);
  const [arkiv, setArkiv] = useState<ArkivView | null>(null);
  const [campaignError, setCampaignError] = useState("");
  const [refund, setRefund] = useState<{ txHash: string; amount: bigint } | null>(null);
  const [topUp, setTopUp] = useState("0.5");
  const [toppedUp, setToppedUp] = useState<{ txHash: string; amount: string } | null>(null);
  const [settlement, setSettlement] = useState<Settlement | null>(null);
  const [copied, setCopied] = useState(false);

  const setField = (k: keyof Brief) => (v: string) => setBrief((b) => ({ ...b, [k]: v }));
  const toggle = (text: string) => setPicked((p) => (p.includes(text) ? p.filter((t) => t !== text) : p.length >= MAX_PICK ? p : [...p, text]));
  const preview = useRotate(picked);

  // a share link like /brand?c=12 opens straight on that campaign's dashboard
  useEffect(() => {
    const c = new URLSearchParams(window.location.search).get("c");
    if (c && /^\d+$/.test(c)) { setTab("dash"); setLookupId(c); void loadCampaign(c); }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (busy === "fund") notch.set("wait", "confirm in your wallet");
    else if (busy) notch.set("think");
    else notch.base("rest");
  }, [busy, notch]);

  async function onConnect() {
    setWalletError("");
    try { setAccount(await connectWallet()); } catch (e) { setWalletError((e as Error).message); }
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
      setHooks((h) => [...res.hooks, ...h.filter((x) => x.format === "own")]);
      setDropped(res.dropped);
      setPicked((p) => (p.length ? p : res.hooks.slice(0, MIN_PICK).map((h) => h.text)));
      setFilter("all");
    } catch (e) {
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
    try { budgetWei = parseNear(budget); rateWei = parseNear(rate); } catch { return setError("Budget and price must be numbers."); }
    const h = Number(hours);
    if (!(rateWei > 0n)) return setError("Price per view must be more than 0.");
    if (budgetWei < rateWei) return setError("Budget must cover at least one view.");
    if (!(h > 0)) return setError("Duration must be more than 0 hours.");

    setBusy("check");
    try {
      await checkCampaign(brief, picked, url.trim(), email.trim()); // refuse here, before any money moves
    } catch (e) {
      setBusy("");
      return setError(`The server refused before any money moved: ${(e as Error).message}`);
    }
    setBusy("fund");
    try {
      const line = picked.join("\n");
      const endTime = BigInt(Math.floor(Date.now() / 1000 + h * 3600));
      const { txHash, campaignId } = await createCampaign({ account, line, budgetWei, rateWei, endTime });
      let recordWarning: string | undefined;
      setBusy("record");
      try {
        await recordCampaign({ campaignId: campaignId.toString(), hooks: picked, moments: picked.map((x) => moments[x] ?? "any"), lineHash: lineHash(line), brand: account, txHash, url: url.trim(), brief, email: email.trim() || undefined });
      } catch (e) {
        recordWarning = `Paid onchain, but the server didn't save your hooks: ${(e as Error).message}. Your budget is safe; contact us with the receipt.`;
      }
      setFunded({ campaignId, txHash, hooks: picked, budgetWei, rateWei, endTime, recordWarning });
      setLookupId(campaignId.toString());
      if (!recordWarning) notch.set("done", `campaign #${campaignId} is live`);
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (e) {
      setError(`Nothing was paid: ${(e as Error).message.split("\n")[0]}`);
    } finally {
      setBusy("");
    }
  }

  async function loadCampaign(id: string) {
    setCampaignError("");
    setRefund(null);
    setToppedUp(null);
    setSettlement(null);
    if (!/^\d+$/.test(id)) return setCampaignError("Enter a campaign ID number, like 2.");
    setBusy("lookup");
    try {
      const [l, s, a] = await Promise.all([readCampaign(BigInt(id)), campaignStats(id).catch(() => null), arkivCampaign(id).catch(() => null)]);
      setLookup(l);
      setStats(s);
      setArkiv(a);
      window.history.replaceState(null, "", `/brand?c=${id}`);
    } catch (e) {
      setLookup(null);
      setCampaignError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function run(kind: string, f: () => Promise<void>) {
    setCampaignError("");
    setBusy(kind);
    try { await f(); } catch (e) { setCampaignError((e as Error).message.split("\n")[0]); } finally { setBusy(""); }
  }
  const onSettle = () => run("settle", async () => {
    setSettlement(null);
    setSettlement(await settleImpressions(lookupId));
    setLookup(await readCampaign(BigInt(lookupId)));
  });
  const onClose = () => run("close", async () => {
    if (!account) throw new Error("Connect the wallet that created this campaign first.");
    const res = await closeCampaign(account, BigInt(lookupId));
    setRefund({ txHash: res.txHash, amount: res.refund });
    setLookup(await readCampaign(BigInt(lookupId)));
  });
  const onTopUp = (e: React.FormEvent) => {
    e.preventDefault();
    setToppedUp(null);
    return run("topup", async () => {
      if (!account) throw new Error("Connect the wallet that created this campaign first.");
      let wei: bigint;
      try { wei = parseNear(topUp); } catch { throw new Error("Enter an amount in NEAR, like 0.5."); }
      if (wei <= 0n) throw new Error("Enter an amount in NEAR, like 0.5.");
      const txHash = await topUpCampaign(account, BigInt(lookupId), wei);
      setToppedUp({ txHash, amount: topUp });
      setLookup(await readCampaign(BigInt(lookupId)));
    });
  };

  function share(id: string) {
    void navigator.clipboard?.writeText(`${window.location.origin}/brand?c=${id}`);
    toast("Link copied");
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }
  function startAnother() {
    setFunded(null); setHooks([]); setPicked([]); setDropped([]); setMoments({}); setTab("new");
    window.history.replaceState(null, "", "/brand");
  }

  const estimate = (() => {
    try { const r = parseNear(rate); return r > 0n ? (parseNear(budget) / r).toString() : "–"; } catch { return "–"; }
  })();
  const fundLabel = busy === "check" ? "Checking your hooks…" : busy === "fund" ? "Confirm in your wallet…" : busy === "record" ? "Saving your hooks…" : "";
  const formats = [...FORMATS, "own" as const].filter((f) => hooks.some((h) => h.format === f));
  const groups = formats.filter((f) => filter === "all" || f === filter).map((f) => ({ f, list: hooks.filter((h) => h.format === f) }));
  const aiHooks = hooks.filter((h) => h.format !== "own");
  const allDropped = !aiHooks.length && dropped.length > 0;
  const n = picked.length;
  const ownLen = own.trim().length;

  // ---------- receipt ----------
  if (funded) {
    const unsaved = !!funded.recordWarning;
    return (
      <>
        <div className="wrap narrow" style={{ maxWidth: 1040 }}>
          <div className="end" style={{ paddingBottom: 20 }}>
            {unsaved && <div className="bad" role="alert" style={{ maxWidth: "62ch", textAlign: "left", padding: "14px 16px", borderRadius: "var(--r-field)", background: "var(--surface)" }}>{funded.recordWarning}</div>}
            <span className="pill live"><i />Campaign #{funded.campaignId.toString()} · {unsaved ? "paid, not saved" : "live"}</span>
            <h1 className="dsp">{unsaved ? "Paid. Hooks not saved yet." : "Your campaign is live."}</h1>
            <p>{unsaved ? "Nothing shows to developers until the hooks are saved. Keep the receipt below; it proves the payment." : "Developers will see your hooks the next time their coding agent starts working. You pay only for real, verified views."}</p>
            {!unsaved && <ReceiptStage lines={funded.hooks} />}
          </div>
          <div className="flow c3">
            <div><i>Budget</i><span className="v">{formatNear(funded.budgetWei)}</span><p>NEAR</p></div>
            <div><i>Price per view</i><span className="v">{formatNear(funded.rateWei)}</span><p>NEAR</p></div>
            <div><i>Estimated views</i><span className="v">{(funded.budgetWei / funded.rateWei).toString()}</span><p>an estimate, not a promise</p></div>
            <div style={{ gridColumn: "span 2" }}><i>Ends</i><b>{formatWhen(Number(funded.endTime) * 1000)}</b><p>Views are paid until 1 hour later, then the rest is refunded.</p></div>
            <div><i>Receipt</i><Tx hash={funded.txHash} /></div>
          </div>
          <div className="actions" style={{ justifyContent: "center", marginTop: 30 }}>
            {unsaved ? (
              <>
                <button type="button" className="btn solid" onClick={() => { void navigator.clipboard?.writeText(`Campaign #${funded.campaignId} · tx ${funded.txHash}`); toast("Receipt copied"); }}>Copy receipt</button>
                <a className="btn ghost" href={`mailto:help@gremlo.dev?subject=${encodeURIComponent(`Campaign #${funded.campaignId} hooks not saved`)}&body=${encodeURIComponent(`Receipt: ${funded.txHash}`)}`}>Contact us</a>
              </>
            ) : (
              <>
                <button type="button" className="btn solid" onClick={() => { const id = funded.campaignId.toString(); setFunded(null); setTab("dash"); void loadCampaign(id); }}>View dashboard</button>
                <button type="button" className="btn ghost" onClick={() => share(funded.campaignId.toString())}>{copied ? "Link copied" : "Copy share link"}</button>
                <button type="button" className="btn" onClick={startAnother}>Start another</button>
              </>
            )}
          </div>
        </div>
      </>
    );
  }

  const head = (
    <div className="wrap">
      {tab === "dash" ? <div style={{ height: 36 }} /> : (
        <div className="sec-head">
          <div><div className="eyebrow">For brands</div><h1 className="dsp">Put your hook<br />on the sign.</h1></div>
          <p>Your hook, carried across a developer’s screen by a tiny pet while their AI agent works. Pay per real, verified view.</p>
        </div>
      )}
      <nav className="tabs" aria-label="Brand console">
        <a href="/brand" aria-current={tab === "new" ? "page" : undefined} onClick={(e) => { e.preventDefault(); setTab("new"); window.history.replaceState(null, "", "/brand"); }}>New campaign</a>
        <a href={lookupId ? `/brand?c=${lookupId}` : "/brand"} aria-current={tab === "dash" ? "page" : undefined} onClick={(e) => { e.preventDefault(); setTab("dash"); }}>Campaign dashboard</a>
      </nav>
    </div>
  );

  // ---------- dashboard ----------
  if (tab === "dash") {
    return <>{head}<div className="wrap">{dashboard()}</div></>;
  }

  // ---------- new campaign ----------
  const briefBad = hooksError && !hooksError.startsWith("Couldn't") && !hooksError.startsWith("A line") && !hooksError.startsWith("That hook");
  return (
    <>
      {head}
      <div className="wrap">
        <div className="panel wallet">
          {account
            ? <><span className="pill"><i />Connected</span><span>Paying from <span className="acct">{account}</span></span></>
            : <><button type="button" className="btn ghost sm" onClick={onConnect}>Connect wallet</button><p>You pay from your own wallet. Nothing moves until you confirm there.</p></>}
        </div>
        {walletError && <div className="bad" role="alert">{walletError}</div>}

        <div className="build">
          <div>
            <section className="step" id="s1">
              <div className="sub-head"><div><div className="eyebrow">Your brief</div><h2><span className="num">01</span>Your product</h2></div><span className="n">the pet writes from this, nothing else</span></div>
              <Field id="what" label="What is it?" value={brief.product} onChange={setField("product")} ph="Clearlog, log search for TypeScript teams" bad={!!briefBad && !brief.product.trim()} />
              <div className="grid2">
                <Field id="who" label="Who is it for?" value={brief.audience} onChange={setField("audience")} max={120} ph="backend developers" bad={!!briefBad && !brief.audience.trim()} />
                <Field id="offer" label="Offer" value={brief.offer} onChange={setField("offer")} max={120} opt ph="first 1M logs free" />
              </div>
              <Field id="proof" label="Proof points" value={brief.proof} onChange={setField("proof")} area max={600} opt ph={"Searches a day of logs in 80ms\nUsed by 400 TypeScript teams"}
                hint="One per line. Hooks may only use numbers and claims from here. Promises of returns or profit are never allowed." />
              <div className="grid2">
                <Field id="cta" label="Call to action" value={brief.cta} onChange={setField("cta")} max={40} ph="Try it free" bad={!!briefBad && !brief.cta.trim()} />
                <Field id="link" label="Link" value={url} onChange={setUrl} max={300} ph="https://" bad={!!briefBad && !/^https:\/\/[^\s]+\.[^\s]+/.test(url.trim())} />
              </div>
              <label className="check"><input type="checkbox" checked={attest} onChange={(e) => setAttest(e.target.checked)} /><span>These proof points are our own claims, and they’re accurate.</span></label>
              {busy === "hooks" ? (
                <div className="panel writing" role="status">
                  <Pet species="byte" row="tools" fps={7} scale={0.42} />
                  <p><b>Writing 16 hooks…</b>Then every hook is checked against your proof points. This can take up to two minutes.</p>
                  <Elapsed />
                </div>
              ) : (
                <div className="actions"><button type="button" className={`btn ${aiHooks.length ? "ghost" : "solid"}`} onClick={onHooks}>{aiHooks.length ? "Write new hooks" : "Write my hooks"}</button></div>
              )}
              {hooksError && !(hooks.length || dropped.length) && <div className="bad" role="alert">{hooksError}</div>}
            </section>

            {(hooks.length > 0 || dropped.length > 0 || (hooksError && hooksError.startsWith("Couldn't"))) && busy !== "hooks" && (
              <section className="step" id="s2">
                <div className="sub-head"><div><div className="eyebrow">Your lines</div><h2><span className="num">02</span>Pick {MIN_PICK} to {MAX_PICK} hooks</h2></div><span className="n" role="status">Picked {n} of {MAX_PICK}</span></div>
                <p className="muted" style={{ margin: "0 0 6px", fontSize: 14.5 }}>Traffic is even until each line has 2,000 sightings, then favours the lines developers open.</p>
                {hooksError && <div className="bad" role="alert">{hooksError}</div>}
                {formats.length > 1 && (
                  <div className="seg sm" role="group" aria-label="Filter by format" style={{ marginTop: 16 }}>
                    <button type="button" aria-pressed={filter === "all"} onClick={() => setFilter("all")}>All</button>
                    {formats.map((f) => <button key={f} type="button" aria-pressed={filter === f} onClick={() => setFilter(f)}>{FORMAT_LABEL[f]}</button>)}
                  </div>
                )}
                {allDropped && (
                  <div className="panel" style={{ marginTop: 18 }}>
                    <b style={{ color: "var(--fg)" }}>None of the hooks passed the claim checks.</b>
                    <p className="muted" style={{ margin: "6px 0 0", fontSize: 14 }}>Usually the proof points are too thin. Add a number you can stand behind, then write again, or write your own below.</p>
                  </div>
                )}
                {groups.map(({ f, list }) => (
                  <div key={f}>
                    <div className="fmt">{FORMAT_LABEL[f]}</div>
                    <div className="lines">
                      {list.map((h) => {
                        const on = picked.includes(h.text);
                        return (
                          <button key={h.text} type="button" className="line" aria-pressed={on} disabled={!on && n >= MAX_PICK} onClick={() => toggle(h.text)}>
                            <span className="box" />
                            <span className="tx"><b>{h.text}</b><small><span>{h.requestId ? `written by AI · ${h.requestId}` : "written by you"}</span><span>{h.text.length}/{MAX_HOOK}</span></small></span>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ))}
                {n > 0 && (
                  <>
                    <div className="fmt">When should each line show?</div>
                    <p className="muted" style={{ margin: "0 0 6px", fontSize: 14 }}>The pet works out the moment on the developer’s Mac; nothing about their work is sent.</p>
                    <div className="moments">
                      {picked.map((line) => (
                        <div key={line} className="moment">
                          <b>{line}</b>
                          <div className="seg sm" role="group" aria-label={`Moment for “${line}”`}>
                            {MOMENTS.map(([k, l]) => <button key={k} type="button" aria-pressed={(moments[line] ?? "any") === k} onClick={() => setMoments({ ...moments, [line]: k })}>{l}</button>)}
                          </div>
                        </div>
                      ))}
                    </div>
                  </>
                )}
                {dropped.length > 0 && (
                  <details className="dropped" open={allDropped}>
                    <summary>{dropped.length} hook{dropped.length === 1 ? "" : "s"} didn’t pass the claim checks</summary>
                    <ul>{dropped.map((d, i) => <li key={i}>{d.text} <span>— {d.reason}</span></li>)}</ul>
                  </details>
                )}
                <div className="fmt" style={{ marginTop: 30 }}>Write your own</div>
                <div className="field" style={{ maxWidth: 560 }}>
                  <label htmlFor="own" className="sr">Your own line</label>
                  <div className="inline">
                    <input id="own" value={own} onChange={(e) => setOwn(e.target.value)} maxLength={MAX_HOOK} placeholder={`${MIN_HOOK} to ${MAX_HOOK} characters`} disabled={n >= MAX_PICK}
                      onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); onAddOwn(); } }} aria-describedby="ownc" />
                    <button type="button" className="btn ghost sm" style={{ minHeight: 54 }} onClick={onAddOwn} disabled={!own.trim() || n >= MAX_PICK}>Add</button>
                  </div>
                  <span id="ownc" className={`count${ownLen > 0 && ownLen < MIN_HOOK ? " over" : ""}`}>{ownLen}/{MAX_HOOK}</span>
                  {n >= MAX_PICK && <p className="hint">You’ve picked {MAX_PICK}. Unpick one to add your own.</p>}
                </div>
              </section>
            )}

            <section className="step" id="s3">
              <div className="sub-head"><div><div className="eyebrow">Pay</div><h2><span className="num">03</span>Budget</h2></div>{hooks.length > 0 && <span className="n">refunds whatever isn’t spent</span>}</div>
              {hooks.length === 0 ? <p className="muted">Write or add a hook first. Budget opens after that.</p> : (
                <>
                  <div className="grid3">
                    <Field id="bud" label="Total budget" value={budget} onChange={setBudget} suffix="NEAR" />
                    <Field id="ppv" label="Price per view" value={rate} onChange={setRate} suffix="NEAR" />
                    <Field id="hrs" label="Runs for" value={hours} onChange={setHours} suffix="hours" />
                  </div>
                  <p className="note" style={{ marginTop: -6 }}>{Number(hours) > 0 ? `Ends ${endsAt || "…"}. Views can still be paid for 1 hour after that; then the unspent budget is refunded.` : "Enter the hours it should run."}</p>
                  <Field id="em" label="Email for budget alerts and a weekly report" value={email} onChange={setEmail} max={254} opt type="email" hint="Only used to email you about this campaign. Never shown or shared." />
                </>
              )}
            </section>
          </div>

          <aside className="summary" aria-label="Campaign summary">
            <div className="panel" style={{ display: "flex", flexDirection: "column", gap: 16 }}>
              <div className="lbl">Preview · what developers see</div>
              <div className="stage">
                {preview ? <span style={{ marginBottom: 14 }}><Plate species={PREVIEW} line={preview} brand={brief.product.split(",")[0].trim() || "your brand"} scale={0.6} k={4} /></span>
                  : <p className="mono faint" style={{ alignSelf: "center", fontSize: 12, textAlign: "center", padding: "0 24px" }}>Pick a line and it shows here, on the pet’s sign.</p>}
              </div>
              <dl className="kvs">
                <dt>Lines</dt><dd>{n} of {MAX_PICK} picked</dd>
                <dt>Budget</dt><dd>{n ? `${budget} NEAR` : "—"}</dd>
                <dt>Per view</dt><dd>{n ? `${rate} NEAR` : "—"}</dd>
                <dt>Runs</dt><dd>{n ? `${hours} hours` : "—"}</dd>
              </dl>
              <div className="est"><b>{n ? estimate : "–"}</b><span>views, roughly, at this price. Any unspent budget is refunded when the campaign ends.</span></div>
              <button type="button" className="btn solid" onClick={onFund} disabled={!account || !!busy || n < MIN_PICK} aria-busy={!!fundLabel}>
                {fundLabel ? <><span className="spin" />{fundLabel}</> : "Fund campaign"}
              </button>
              {fundLabel && (
                <p className="note" role="status" style={{ margin: 0 }}>
                  {busy === "fund" ? `Your wallet has the request. Approve the deposit of ${budget} NEAR there.` : busy === "record" ? "Paid. Saving the line text to the server." : "The server checks the same rules before any money moves."}
                </p>
              )}
              {!account ? <p className="note" style={{ margin: 0 }}>Connect your wallet at the top to fund.</p> : (!n && !busy ? <p className="note" style={{ margin: 0 }}>Pick at least {MIN_PICK} hook first.</p> : null)}
              {error && <div className="bad" role="alert" style={{ margin: 0 }}>{error}</div>}
              <span className="contract">Contract: <a className="hash" href={addressLink(VAULT_ID)} target="_blank" rel="noreferrer">{VAULT_ID || "—"}</a></span>
            </div>
          </aside>
        </div>
        <div className="mobibar">
          <span>{n ? `${n} line${n === 1 ? "" : "s"} · ~${estimate} views · ${budget} NEAR` : "Pick a hook to fund"}</span>
          <a className="btn solid sm" href="#s3">Review &amp; fund</a>
        </div>
      </div>
    </>
  );

  function dashboard() {
    const look = (
      <form className="lookup" onSubmit={(e) => { e.preventDefault(); void loadCampaign(lookupId); }}>
        <div className="field"><label htmlFor="cid">Campaign ID</label><input id="cid" value={lookupId} onChange={(e) => setLookupId(e.target.value.trim())} inputMode="numeric" placeholder="like 2" /></div>
        <button type="submit" className="btn ghost" disabled={busy === "lookup"}>{busy === "lookup" ? <><span className="spin" />Checking…</> : "Check"}</button>
        <button type="button" className="btn ghost" onClick={onSettle} disabled={!lookup || busy === "settle"}>{busy === "settle" ? <><span className="spin" />Settling…</> : "Settle views"}</button>
      </form>
    );
    if (!lookup) {
      return (
        <>
          {look}
          {campaignError ? <div className="bad" role="alert" style={{ marginTop: 22 }}>{campaignError}</div> : (
            <div className="panel" style={{ marginTop: 28, textAlign: "center", padding: "48px 24px" }}>
              <Pet species={PREVIEW} row="gaze" fps={3} scale={0.5} style={{ margin: "0 auto" }} />
              <p className="muted" style={{ margin: "12px auto 0" }}>Enter the number you got after funding, shown as Campaign #N. A share link <span className="mono">/brand?c=3</span> opens straight here.</p>
            </div>
          )}
        </>
      );
    }
    const l = lookup;
    const now = BigInt(Math.floor(Date.now() / 1000));
    const st = l.closed ? "closed" : l.endTime > now ? "running" : l.endTime + 3600n > now ? "window" : "past";
    const pct = l.budget > 0n ? Number((l.spent * 100n) / l.budget) : 0; // integer math on yocto
    const status = {
      running: `Running until ${formatWhen(Number(l.endTime) * 1000)}.`,
      window: `Ended. Views can be settled until ${formatWhen(Number(l.endTime + 3600n) * 1000)}; then it can be closed and refunded.`,
      past: "Ended and the settlement window has passed. Close it to refund what’s left.",
      closed: "Closed. Unspent budget was refunded.",
    }[st];
    const pill = { running: <span className="pill live"><i />Running</span>, window: <span className="pill warn"><i />Ended · settling</span>, past: <span className="pill warn"><i />Ended</span>, closed: <span className="pill off"><i />Closed</span> }[st];
    const warn = pct >= 100 ? "Budget used up: your hooks have stopped showing." : pct >= 50 ? `${pct}% of the budget is spent.` : "";
    const lines = stats?.lines ?? null;
    const rows = stats ? stats.views.map((v, i) => ({ i, v, c: stats.clicks[i] ?? 0 })).filter((r) => r.v || r.c || lines?.[r.i]) : [];
    const id = lookupId;
    return (
      <>
        {look}
        {campaignError && <div className="bad" role="alert" style={{ marginTop: 22 }}>{campaignError}</div>}
        <div className="dash-head">
          <div><div className="eyebrow">Brand · {l.brand}</div><h1 className="dsp" style={{ fontSize: "clamp(48px, 7vw, 100px)", margin: "10px 0 0" }}>Campaign #{id}</h1></div>
          <div className="actions">{pill}<button type="button" className="btn ghost sm" onClick={() => share(id)}>{copied ? "Link copied" : "Copy share link"}</button></div>
        </div>
        <div className="two">
          <div>
            <div className="panel">
              <div className="bline">
                <span>Budget <b>{formatNear(l.budget)} NEAR</b></span>
                <span>spent <b>{formatNear(l.spent)} NEAR</b></span>
                <span>left <b>{formatNear(l.remaining)} NEAR</b></span>
              </div>
              <div className={`meter${pct >= 80 ? " hot" : ""}`} role="meter" aria-label="Budget spent" aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct} aria-valuetext={`${pct}% spent`}><i style={{ width: `${Math.min(100, pct)}%` }} /></div>
              {warn && !l.closed && <p style={{ margin: "14px 0 0", color: "var(--fg)", fontWeight: 600 }}>{warn}{st === "running" && <span className="muted" style={{ fontWeight: 400 }}> Top up below to keep them running.</span>}</p>}
              {st === "running" && (
                <form className="inline" style={{ marginTop: 18, alignItems: "flex-end", gap: 8, flexWrap: "wrap" }} onSubmit={onTopUp}>
                  <div className="field" style={{ margin: 0, flex: "0 1 220px" }}><label htmlFor="tu">Add budget (NEAR)</label><input id="tu" value={topUp} onChange={(e) => setTopUp(e.target.value)} inputMode="decimal" style={{ minHeight: 46, padding: "10px 14px" }} /></div>
                  <button type="submit" className="btn solid" style={{ minHeight: 46 }} disabled={busy === "topup"}>{busy === "topup" ? <><span className="spin" />Topping up…</> : "Top up"}</button>
                </form>
              )}
              {toppedUp && <p className="note">Added {toppedUp.amount} NEAR: <Tx hash={toppedUp.txHash} /></p>}
              {st === "past" && (
                <div className="actions" style={{ marginTop: 18 }}>
                  <button type="button" className="btn solid" onClick={onClose} disabled={busy === "close"}>{busy === "close" ? <><span className="spin" />Closing…</> : "Close and refund"}</button>
                  <span className="note" style={{ margin: 0 }}>Refunds {formatNear(l.remaining)} NEAR to {l.brand}</span>
                </div>
              )}
              {refund && <p className="note">Refunded {formatNear(refund.amount)} NEAR: <Tx hash={refund.txHash} /></p>}
              <p className="note" style={{ marginTop: 16 }}>{status}</p>
            </div>

            {settlement && (
              settlement.error ? (
                <div className="panel settle">
                  <div className="bad" role="alert" style={{ margin: 0 }}>Settlement stopped: {settlement.error}</div>
                  <p className="muted" style={{ margin: "8px 0 0", fontSize: 14 }}>Views before the break were paid. The rest stay queued; nothing is charged for them.</p>
                </div>
              ) : settlement.count === 0 ? (
                <div className="panel settle" role="status"><h3>Settle views</h3><p className="muted" style={{ margin: 0 }}>No views queued for this campaign yet.</p></div>
              ) : (
                <div className="panel settle" role="status">
                  <h3>Paid {settlement.count} view{settlement.count === 1 ? "" : "s"}, {formatNear(BigInt(settlement.amount))} NEAR{settlement.seeded && <> <span className="ex">seeded, local sandbox</span></>}</h3>
                  <ul>{settlement.settled.map((s) => <li key={s.txHash}>{s.count} to pet <span className="mono">{s.petKey}</span>: <Tx hash={s.txHash} /></li>)}</ul>
                </div>
              )
            )}

            <div className="sub-head" style={{ paddingTop: 36 }}><h2 style={{ fontSize: 20 }}>How each line is doing</h2><span className="n">Hook # · line · views · clicks · rate</span></div>
            {stats === null ? (
              <div className="panel">
                <div className="bad" role="alert" style={{ margin: 0 }}>Can’t read view stats from the server right now.</div>
                <p className="muted" style={{ margin: "8px 0 0", fontSize: 14 }}>Budget and status above come straight from the campaign contract, so they’re still right.</p>
              </div>
            ) : stats && (
              <>
                <table className="tbl">
                  <thead><tr><th>Hook</th><th className="num">Views</th><th className="num">Clicks</th><th className="num">Click rate</th></tr></thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.i} className={stats.best === r.i ? "best" : undefined}>
                        <td data-th="Hook" className="wide"><b style={{ color: "var(--fg)" }}>#{r.i + 1}</b> {lines?.[r.i] && <span className="muted">{lines[r.i]}</span>}</td>
                        <td data-th="Views" className="num">{r.v}</td>
                        <td data-th="Clicks" className="num">{r.c}</td>
                        <td data-th="Click rate" className="num">{r.v ? `${((r.c / r.v) * 100).toFixed(1)}%` : "–"}</td>
                      </tr>
                    ))}
                    {rows.length === 0 && <tr><td colSpan={4} className="wide"><span className="muted">No views yet. They appear here as developers’ agents start working.</span></td></tr>}
                  </tbody>
                </table>
                <ul className="facts" style={{ marginTop: 16 }}>
                  {stats.best != null && <li className="good">Best hook so far: #{stats.best + 1}, {((stats.clicks[stats.best] / stats.views[stats.best]) * 100).toFixed(1)}% of views clicked.</li>}
                  {stats.heldViews > 0 && <li>{stats.heldViews} view{stats.heldViews === 1 ? "" : "s"} in the fraud check{stats.holdbackHours ? ` (paid after ${stats.holdbackHours}h)` : ""}.</li>}
                  {Object.entries(stats.voided).map(([reason, k]) => <li key={reason} className="hot">{k} view{k === 1 ? "" : "s"} voided, not charged: {reason}.</li>)}
                  {stats.pendingViews > 0 && <li>{stats.pendingViews} view{stats.pendingViews === 1 ? "" : "s"} waiting to be settled.</li>}
                  {stats.moments && Object.keys(stats.moments).length > 0 && <li>By moment: {Object.entries(stats.moments).map(([m, k]) => `${m} ${k ?? "(under 50 pets)"}`).join(" · ")}</li>}
                  {stats.paused && stats.paused.length > 0 && <li className="hot">Paused by reports: line {stats.paused.map((i) => i + 1).join(", ")}.</li>}
                  {stats.emailAlerts && <li>Budget alerts and the weekly report go to the email you gave.</li>}
                </ul>
              </>
            )}
          </div>
          <div>
            <div className="panel">
              <div className="lbl" style={{ marginBottom: 12 }}>Proof</div>
              <p style={{ margin: "0 0 14px", fontSize: 14.5, color: "var(--fg)" }}>Every counted view is a signed report from a pet. <a href={`${SERVER_URL}/campaigns/${id}/log`} target="_blank" rel="noreferrer">Public log</a> · check it yourself:</p>
              <div className="term"><span className="c">$</span> <b>gremlo verify {id}</b><br /><span className="c">checks every signed view against the bill</span></div>
              {arkiv?.on && (
                <p className="muted" style={{ margin: "16px 0 0", fontSize: 13.5 }}>
                  {arkiv.card
                    ? <>Mirrored on Arkiv. Campaign card <span className="mono">{arkiv.card.key.slice(0, 6)}…{arkiv.card.key.slice(-4)}</span>, expires at Arkiv block {arkiv.card.expiresAt}. {arkiv.receipts.length} settlement receipt{arkiv.receipts.length === 1 ? "" : "s"}. <a href={arkiv.explorer} target="_blank" rel="noreferrer">Arkiv explorer</a></>
                    : "Not on Arkiv yet. It’s published when the campaign is saved."}
                </p>
              )}
            </div>
            {lines && lines.length > 0 && (
              <div className="panel" style={{ marginTop: 16 }}>
                <div className="lbl" style={{ marginBottom: 14 }}>Live preview</div>
                <DashPreview lines={lines} />
              </div>
            )}
          </div>
        </div>
      </>
    );
  }
}

function ReceiptStage({ lines }: { lines: string[] }) {
  const line = useRotate(lines);
  return (
    <div className="stage receipt-stage">
      {line && <span style={{ marginBottom: 20 }}><Plate species={PREVIEW} line={line} brand="your brand" scale={0.7} k={5} /></span>}
      <span className="cap lbl">Preview · what developers see</span>
    </div>
  );
}

function DashPreview({ lines }: { lines: string[] }) {
  const line = useRotate(lines);
  return <div className="stage" style={{ height: 200 }}>{line && <span style={{ marginBottom: 14 }}><Plate species={PREVIEW} line={line} scale={0.5} k={3.5} /></span>}</div>;
}
