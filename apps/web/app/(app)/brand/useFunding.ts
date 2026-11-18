"use client";

import { useEffect, useState } from "react";
import { ApiError, checkCampaign, FORMATS, recordCampaign, suggestHooks, type Brief, type Dropped, type Hook } from "@/lib/api";
import { connectWallet, createCampaign, lineHash } from "@/lib/chain";
import { clearDraft, keepDraft, loadDraft, type Draft } from "@/lib/draft";
import { formatNear, formatWhen, minBudget, parseNear, viewsFor } from "@/lib/config";
import { plainError } from "@/lib/errors";
import { PaidError, UnsureError } from "@/lib/paid";
import { useNotch } from "@/components/Shell";
import { useRotate } from "@/components/useRotate";
import { emptyBrief, MAX_HOOK, MAX_PICK, MIN_HOOK, MIN_PICK, type Funded } from "./shared";

/** The new-campaign flow: the brief, the hooks, the budget, paying, and recovering a payment whose hooks weren't saved. */
export function useFunding({ account, setAccount, busy, setBusy, onPaid }: { account: string | null; setAccount: (a: string | null) => void; busy: string; setBusy: (b: string) => void; onPaid: (id: string) => void }) {
  const notch = useNotch();
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
  useEffect(() => {
    const h = Number(hours);
    setEndsAt(h > 0 ? formatWhen(Date.now() + h * 3_600_000) : "");
  }, [hours]);
  const [walletError, setWalletError] = useState("");
  const [error, setError] = useState("");
  const [hooksError, setHooksError] = useState("");
  const [funded, setFunded] = useState<Funded | null>(null);
  // hooks of a paid campaign the server hasn't saved yet; kept on this device so Retry works after a reload too
  const [unsavedDraft, setUnsavedDraft] = useState<Draft | null>(null);
  const [retrying, setRetrying] = useState(false);
  const [retryError, setRetryError] = useState("");
  const [paidTx, setPaidTx] = useState<string | null>(null);
  useEffect(() => {
    setUnsavedDraft(loadDraft());
  }, []);
  const setField = (k: keyof Brief) => (v: string) => setBrief((b) => ({ ...b, [k]: v }));
  const toggle = (text: string) => setPicked((p) => (p.includes(text) ? p.filter((t) => t !== text) : p.length >= MAX_PICK ? p : [...p, text]));
  const preview = useRotate(picked);

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
    if (!brief.cta.trim()) return 'Add a call to action, like "Try it free".';
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
    try {
      budgetWei = parseNear(budget);
      rateWei = parseNear(rate);
    } catch {
      return setError("Budget and price must be numbers.");
    }
    const h = Number(hours);
    if (!(rateWei > 0n)) return setError("Price per view must be more than 0.");
    if (budgetWei < minBudget(rateWei)) return setError(`Budget must be at least ${formatNear(minBudget(rateWei))} NEAR: one view plus a one-time storage fee.`);
    if (!(h >= 1)) return setError("Run it for at least 1 hour.");

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
      const draft: Draft = {
        campaignId: campaignId.toString(),
        hooks: picked,
        moments: picked.map((x) => moments[x] ?? "any"),
        lineHash: lineHash(line),
        brand: account,
        txHash,
        url: url.trim(),
        brief,
        email: email.trim() || undefined,
      };
      try {
        await recordCampaign(draft);
      } catch (e) {
        keepDraft(draft); // the hook text lives only in this page; keep it so Retry survives a reload
        setUnsavedDraft(draft);
        recordWarning = `Your payment went through, but the server didn't save your hooks yet: ${plainError(e)} Your budget is safe. Your hooks are kept on this device; press Retry.`;
      }
      setFunded({ campaignId, txHash, hooks: picked, budgetWei, rateWei, endTime, recordWarning });
      onPaid(campaignId.toString());
      if (!recordWarning) notch.set("done", `campaign #${campaignId} is live`);
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (e) {
      if (e instanceof PaidError) {
        setPaidTx(e.txHash);
        setError(`${e.message} Open the receipt below; it shows the campaign number to look up on the Campaign dashboard tab.`);
      } else if (e instanceof UnsureError) setError(`${e.message} If it went through, the transaction shows the campaign number; look it up on the Campaign dashboard tab.`);
      else setError(`Nothing was paid: ${plainError(e)}`);
    } finally {
      setBusy("");
    }
  }

  async function retrySave() {
    if (!unsavedDraft) return;
    setRetrying(true);
    setRetryError("");
    try {
      await recordCampaign(unsavedDraft);
      clearDraft();
      const id = unsavedDraft.campaignId;
      setUnsavedDraft(null);
      setFunded((f) => (f && f.campaignId.toString() === id ? { ...f, recordWarning: undefined } : f));
      notch.set("done", `campaign #${id} is live`);
    } catch (e) {
      setRetryError(plainError(e));
    } finally {
      setRetrying(false);
    }
  }

  const estimate = (() => {
    try {
      const r = parseNear(rate);
      return r > 0n ? viewsFor(parseNear(budget), r).toString() : "–";
    } catch {
      return "–";
    }
  })();
  const fundLabel = busy === "check" ? "Checking your hooks…" : busy === "fund" ? "Confirm in your wallet…" : busy === "record" ? "Saving your hooks…" : "";
  const formats = [...FORMATS, "own" as const].filter((f) => hooks.some((h) => h.format === f));
  const groups = formats.filter((f) => filter === "all" || f === filter).map((f) => ({ f, list: hooks.filter((h) => h.format === f) }));
  const aiHooks = hooks.filter((h) => h.format !== "own");
  const allDropped = !aiHooks.length && dropped.length > 0;
  const n = picked.length;
  const ownLen = own.trim().length;
  const briefBad = hooksError && !hooksError.startsWith("Couldn't") && !hooksError.startsWith("A line") && !hooksError.startsWith("That hook");
  function startAnother() {
    setFunded(null);
    setHooks([]);
    setPicked([]);
    setDropped([]);
    setMoments({});
  }

  return {
    account,
    brief,
    url,
    setUrl,
    attest,
    setAttest,
    email,
    setEmail,
    hooks,
    dropped,
    picked,
    moments,
    setMoments,
    filter,
    setFilter,
    own,
    setOwn,
    budget,
    setBudget,
    rate,
    setRate,
    hours,
    setHours,
    endsAt,
    walletError,
    error,
    hooksError,
    funded,
    setFunded,
    unsavedDraft,
    retrying,
    retryError,
    paidTx,
    setField,
    toggle,
    preview,
    onConnect,
    onHooks,
    onAddOwn,
    onFund,
    retrySave,
    startAnother,
    estimate,
    fundLabel,
    formats,
    groups,
    aiHooks,
    allDropped,
    n,
    ownLen,
    briefBad,
    busy,
  };
}
export type Funding = ReturnType<typeof useFunding>;
