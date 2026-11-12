"use client";

import { useState } from "react";
import { tryHook, type Hook } from "@/lib/api";
import { HookTicker } from "./HookTicker";
import { PetSmall } from "./PetArt";

/** One real NEAR AI call: type a product, the pet holds three example hooks. Rate-limited on the server. */
export function TryHook() {
  const [product, setProduct] = useState("");
  const [busy, setBusy] = useState(false);
  const [hooks, setHooks] = useState<Hook[]>([]);
  const [requestId, setRequestId] = useState("");
  const [error, setError] = useState("");
  async function go(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (product.trim().length < 3) return setError("Say what your product is first.");
    setBusy(true);
    try {
      const r = await tryHook(product.trim(), "developers");
      setHooks(r.hooks);
      setRequestId(r.requestId);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="try">
      <form onSubmit={go} className="try-form">
        <label htmlFor="try-product">Your product</label>
        <div className="own-row">
          <input id="try-product" value={product} onChange={(e) => setProduct(e.target.value)} maxLength={160} placeholder="an AI code reviewer for pull requests" />
          <button disabled={busy} aria-busy={busy}>{busy ? "Writing…" : "Write hooks"}</button>
        </div>
      </form>
      {busy && (
        <div className="thinking" role="status">
          <PetSmall />
          <div><strong>Writing on NEAR AI Cloud…</strong><span className="muted">Real inference, usually 20 to 60 seconds.</span></div>
        </div>
      )}
      {error && <p className="bad" role="alert">{error}</p>}
      {hooks.length > 0 && (
        <>
          <HookTicker hooks={hooks.map((h) => h.text)} scale={1.2} every={3200} label={`Example only · written by AI · request ${requestId.slice(0, 8)}…`} />
          <ul className="try-list">{hooks.map((h) => <li key={h.text}><span className="mono">{h.format}</span>{h.text}</li>)}</ul>
        </>
      )}
    </div>
  );
}
