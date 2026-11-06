"use client";

import { useEffect, useState } from "react";
import { formatEther, parseEther, type Address, type Hash } from "viem";
import { ApiError, recordCampaign, settleImpressions, suggestLines, type Settlement, type SuggestedLine } from "@/lib/api";
import { closeCampaign, connectWallet, createCampaign, lineHash, readCampaign } from "@/lib/chain";
import { addressLink, txLink, VAULT_ADDRESS } from "@/lib/config";
import { PetSmall } from "@/components/PetArt";

/** Seconds since mount, so a long 0G call visibly moves. */
function Elapsed() {
  const [s, setS] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setS((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  return <>{s}s</>;
}

type Funded = { campaignId: bigint; txHash: Hash; line: string; recordWarning?: string };
type Lookup = Awaited<ReturnType<typeof readCampaign>>;

export default function FundCampaign() {
  const [account, setAccount] = useState<Address | null>(null);
  const [brief, setBrief] = useState("");
  const [lines, setLines] = useState<SuggestedLine[]>([]);
  const [picked, setPicked] = useState<number | null>(null);
  const [ownLine, setOwnLine] = useState("");
  const [budget, setBudget] = useState("0.02");
  const [rate, setRate] = useState("0.0001");
  const [hours, setHours] = useState("1");
  const [walletError, setWalletError] = useState(""); // shown next to Connect wallet
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [campaignError, setCampaignError] = useState(""); // lookup, settle and close, shown in "Your campaign"
  const [linesError, setLinesError] = useState("");
  const [funded, setFunded] = useState<Funded | null>(null);

  const [lookupId, setLookupId] = useState("");
  const [lookup, setLookup] = useState<Lookup | null>(null);
  const [refund, setRefund] = useState<{ txHash: Hash; amount: bigint } | null>(null);
  const [settlement, setSettlement] = useState<Settlement | null>(null);

  const chosenLine = picked !== null ? lines[picked]?.text ?? "" : ownLine.trim();

  async function onConnect() {
    setWalletError("");
    try {
      setAccount(await connectWallet());
    } catch (e) {
      setWalletError((e as Error).message);
    }
  }

  async function onSuggest() {
    setLinesError("");
    if (brief.trim().length < 8) {
      setLinesError("Write a sentence about what you sell first.");
      return;
    }
    setBusy("lines");
    try {
      const res = await suggestLines(brief.trim());
      setLines(res.lines ?? []);
      setPicked(res.lines?.length ? 0 : null);
    } catch (e) {
      setLines([]);
      setPicked(null);
      setLinesError(
        e instanceof ApiError && e.status === 404
          ? "The server doesn't have the line-writing route yet. Write your own line below."
          : `Notchi couldn't write lines: ${(e as Error).message}. Try again, or write your own line below.`,
      );
    } finally {
      setBusy("");
    }
  }

  async function onFund() {
    setError("");
    if (!account) return setError("Connect your wallet first.");
    if (!chosenLine) return setError("Pick one of Notchi's lines or write your own.");
    if (chosenLine.length > 60) return setError("Keep the line under 60 characters so it fits on the sign.");
    let budgetWei: bigint, rateWei: bigint;
    try {
      budgetWei = parseEther(budget);
      rateWei = parseEther(rate);
    } catch {
      return setError("Budget and price must be numbers.");
    }
    const h = Number(hours);
    if (!(rateWei > 0n)) return setError("Price per impression must be more than 0.");
    if (budgetWei < rateWei) return setError("Budget must cover at least one impression.");
    if (!(h > 0)) return setError("Duration must be more than 0 hours.");

    setBusy("fund");
    try {
      const endTime = BigInt(Math.floor(Date.now() / 1000 + h * 3600));
      const { txHash, campaignId } = await createCampaign({ account, line: chosenLine, budgetWei, rateWei, endTime });
      let recordWarning: string | undefined;
      try {
        await recordCampaign({
          campaignId: campaignId.toString(),
          line: chosenLine,
          lineHash: lineHash(chosenLine),
          brand: account,
          txHash,
        });
      } catch (e) {
        recordWarning = `Paid onchain, but the server didn't save the line text: ${(e as Error).message}`;
      }
      setFunded({ campaignId, txHash, line: chosenLine, recordWarning });
      setLookupId(campaignId.toString());
    } catch (e) {
      setError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
    }
  }

  async function onLookup() {
    setCampaignError("");
    setRefund(null);
    if (!/^\d+$/.test(lookupId)) return setCampaignError("Enter a campaign ID number, like 2.");
    setBusy("lookup");
    try {
      setLookup(await readCampaign(BigInt(lookupId)));
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

  const nowSec = BigInt(Math.floor(Date.now() / 1000));

  return (
    <>
      <h1>Fund a campaign</h1>
      <p className="lead">Your line, held up by a tiny pet while developers wait on their AI agent. Pay per real impression.</p>

      {!account ? (
        <>
          <button onClick={onConnect}>Connect wallet</button>
          {walletError && <p className="bad">{walletError}</p>}
        </>
      ) : (
        <p className="muted">
          Paying from <span className="mono">{account}</span>
        </p>
      )}

      {!funded && (
        <>
          <div className="card">
            <h2>1. What do you sell?</h2>
            <textarea value={brief} onChange={(e) => setBrief(e.target.value)} placeholder="CI that runs in 30 seconds for TypeScript monorepos." />
            <p>
              <button className="ghost" onClick={onSuggest} disabled={busy === "lines"} aria-busy={busy === "lines"}>
                {busy === "lines" ? "Writing lines…" : "Let Notchi write 3 lines"}
              </button>
            </p>
            {busy === "lines" && (
              <div className="thinking" role="status">
                <PetSmall />
                <div>
                  <strong>Notchi is thinking on 0G…</strong>
                  <span className="muted">
                    This can take up to a minute. <Elapsed />
                  </span>
                </div>
              </div>
            )}
            {linesError && <p className="bad">{linesError}</p>}
            {lines.map((l, i) => (
              <button key={i} className={`sign ${picked === i ? "picked" : ""}`} onClick={() => setPicked(i)}>
                {l.text}
                <small className="mono">written on 0G{l.requestId ? ` · request ${l.requestId}` : ""}</small>
              </button>
            ))}
            <label>Or write your own</label>
            <input
              value={ownLine}
              onChange={(e) => {
                setOwnLine(e.target.value);
                if (e.target.value) setPicked(null);
              }}
              placeholder="Ship faster with Acme CI"
            />
          </div>

          <div className="card">
            <h2>2. Budget</h2>
            <div className="row">
              <div>
                <label>Total budget (0G)</label>
                <input value={budget} onChange={(e) => setBudget(e.target.value)} />
              </div>
              <div>
                <label>Price per impression (0G)</label>
                <input value={rate} onChange={(e) => setRate(e.target.value)} />
              </div>
              <div>
                <label>Runs for (hours)</label>
                <input value={hours} onChange={(e) => setHours(e.target.value)} />
              </div>
            </div>
            <p className="muted">
              About {(() => {
                try {
                  const r = parseEther(rate);
                  return r > 0n ? (parseEther(budget) / r).toString() : "0";
                } catch {
                  return "?";
                }
              })()}{" "}
              impressions. Any unspent budget is refunded when the campaign ends.
            </p>
            {error && <p className="bad">{error}</p>}
            <button onClick={onFund} disabled={!account || busy === "fund"}>
              {busy === "fund" ? "Confirm in your wallet…" : "Fund campaign"}
            </button>
            {!account && <p className="hint">Connect your wallet at the top to fund.</p>}
            <p className="muted">
              Contract:{" "}
              <a className="mono" href={addressLink(VAULT_ADDRESS)} target="_blank" rel="noreferrer">
                {VAULT_ADDRESS}
              </a>
            </p>
          </div>
        </>
      )}

      {funded && (
        <div className="card">
          <h2 className="ok">Campaign #{funded.campaignId.toString()} is live.</h2>
          <button className="sign picked" disabled>
            {funded.line}
          </button>
          <p className="muted">
            Receipt:{" "}
            <a className="mono" href={txLink(funded.txHash)} target="_blank" rel="noreferrer">
              {funded.txHash}
            </a>
          </p>
          {funded.recordWarning && <p className="bad">{funded.recordWarning}</p>}
          <button className="ghost" onClick={() => setFunded(null)}>
            Start another
          </button>
        </div>
      )}

      <div className="card">
        <h2>Your campaign</h2>
        <div className="row">
          <div>
            <label>Campaign ID</label>
            <input value={lookupId} onChange={(e) => setLookupId(e.target.value)} placeholder="1" />
          </div>
        </div>
        <p>
          <button className="ghost" onClick={onLookup} disabled={busy === "lookup"}>
            {busy === "lookup" ? "Checking…" : "Check"}
          </button>{" "}
          <button className="ghost" onClick={onSettle} disabled={busy === "settle"}>
            {busy === "settle" ? "Settling onchain…" : "Settle impressions"}
          </button>
        </p>
        {campaignError && <p className="bad">{campaignError}</p>}
        {settlement && (
          <>
            {settlement.count === 0 && !settlement.error && <p className="muted">No impressions queued for this campaign yet.</p>}
            {settlement.count > 0 && (
              <p className="ok">
                Paid {settlement.count} impression{settlement.count === 1 ? "" : "s"}, {formatEther(BigInt(settlement.amount))} 0G
                {settlement.seeded ? " [seeded, local chain]" : ""}
              </p>
            )}
            {settlement.settled.map((s) => (
              <p key={s.txHash} className="muted">
                {s.count} to pet <span className="mono">{s.petKey}</span>:{" "}
                <a className="mono" href={txLink(s.txHash)} target="_blank" rel="noreferrer">
                  {s.txHash}
                </a>
              </p>
            ))}
            {settlement.error && <p className="bad">Settlement stopped: {settlement.error}</p>}
          </>
        )}
        {lookup && (
          <>
            <p>
              Budget {formatEther(lookup.budget)} 0G · spent {formatEther(lookup.spent)} 0G · left {formatEther(lookup.remaining)}{" "}
              0G
            </p>
            <p className="muted">
              {lookup.closed
                ? "Closed. Unspent budget was refunded."
                : lookup.endTime > nowSec
                  ? `Running until ${new Date(Number(lookup.endTime) * 1000).toLocaleString()}.`
                  : "Ended. It can be closed and refunded once the 1-hour settlement window passes."}
            </p>
            {!lookup.closed && lookup.endTime <= nowSec && (
              <button onClick={onClose} disabled={busy === "close"}>
                {busy === "close" ? "Closing…" : "Close and refund"}
              </button>
            )}
          </>
        )}
        {refund && (
          <p className="ok">
            Refunded {formatEther(refund.amount)} 0G:{" "}
            <a className="mono" href={txLink(refund.txHash)} target="_blank" rel="noreferrer">
              {refund.txHash}
            </a>
          </p>
        )}
      </div>
    </>
  );
}
