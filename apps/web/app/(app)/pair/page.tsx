"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ApiError, getPet, pairDevice } from "@/lib/api";
import { connectWallet, signOwnerMessage } from "@/lib/chain";
import { PRODUCT, VAULT_ID } from "@/lib/config";
import { pairMessage } from "@/lib/pair";
import type { RowName } from "@/lib/species";
import { Pet } from "@/components/Pet";
import { useNotch } from "@/components/Shell";
import "./pair.css";

/** Same id the server derives: first 16 hex chars of SHA-256 over the raw public key. */
async function keyId(b64u: string) {
  const raw = Uint8Array.from(atob(b64u.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", raw));
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

function Art({ row, device }: { row: RowName; device: string }) {
  return (
    <div className="devart" aria-hidden="true">
      <div className="lap"><div className="nt" /><span className="scr"><Pet row={row} fps={3} scale={0.55} /></span></div>
      {device && <span className="key">Secure Enclave key<br /><b>{device}</b></span>}
    </div>
  );
}

export default function Pair() {
  const notch = useNotch();
  const [pet, setPet] = useState<string | null>(null);
  const [asked, setAsked] = useState("");
  const [key, setKey] = useState("");
  const [device, setDevice] = useState("");
  const [account, setAccount] = useState<string | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "signing" | "done" | "badlink" | "unknown">("loading");
  const [message, setMessage] = useState("");

  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const name = q.get("pet"), k = q.get("key");
    if (!name || !k || !/^[A-Za-z0-9_-]{80,100}$/.test(k)) { setState("badlink"); return; }
    setAsked(name);
    setKey(k);
    void keyId(k).then(setDevice);
    getPet(name)
      .then((p) => { setPet(p.name); setState("ready"); })
      .catch((e) => {
        if (e instanceof ApiError && e.status === 404) setState("unknown");
        else { setState("ready"); setMessage((e as Error).message); }
      });
  }, []);

  useEffect(() => {
    if (state === "loading") notch.set("think");
    else if (state === "signing") notch.set("wait", "sign in your wallet");
    else if (state === "done") notch.base("door");
    else notch.base("rest");
  }, [state, notch]);

  async function approve() {
    setMessage("");
    try {
      const a = account ?? (await connectWallet());
      setAccount(a);
      setState("signing");
      const signed = await signOwnerMessage(a, pairMessage(pet!, device));
      await pairDevice(pet!, key, signed);
      setState("done");
    } catch (e) {
      setState("ready");
      setMessage(e instanceof ApiError && e.status === 403 ? "This NEAR account isn’t the pet’s owner, or the key isn’t a full-access key. Connect the account that registered the pet." : (e as Error).message.split("\n")[0]);
    }
  }

  if (state === "done") {
    return (
      <div className="wrap">
        <div className="end">
          <span className="wob"><Pet row="celebrate" fps={8} scale={0.8} /></span>
          <span className="eyebrow">Pair a Mac</span>
          <h1 className="dsp">This Mac is paired.</h1>
          <p>Views, clicks and think calls from this Mac are now signed by its Secure Enclave.</p>
          <p className="mono" style={{ fontSize: 13, color: "var(--fg)" }}>Device {device} paired to {pet}.</p>
          <span className="nofee"><i>✓</i>You can close this tab.</span>
        </div>
      </div>
    );
  }

  const known = state === "ready" || state === "signing" || state === "unknown";
  return (
    <div className="wrap pair">
      <div className="sec-head sm" style={{ gridTemplateColumns: "1fr" }}><div><div className="eyebrow">Pair a Mac</div><h1 className="dsp">Pair this Mac with your pet</h1></div></div>
      {state === "loading" && <><p className="note" role="status"><span className="spin" aria-hidden="true" />Checking the link…</p><Art row="peek" device={device} /></>}
      {known && (
        <>
          <Art row={state === "signing" ? "peek" : "idle"} device={device} />
          <div className="flow c2">
            <div><i>Pet</i><b style={{ fontSize: 22 }}>{state === "unknown" ? `${asked} · not found` : pet}</b></div>
            <div><i>Device</i><b className="mono" style={{ fontSize: 18, wordBreak: "break-all" }}>{device || "—"}</b><p className="mono" style={{ fontSize: 11 }}>first 16 hex of SHA-256 over this Mac’s key</p></div>
          </div>
          <div style={{ margin: "24px 0 18px" }}><span className="nofee"><i>✓</i>No transaction, no fee</span></div>
          <p style={{ margin: "0 0 14px", color: "var(--fg)" }}>Pairing lets this Mac’s Secure Enclave sign your pet’s views and clicks, so nobody else can earn as your pet. You sign one message (NEP-413) with the NEAR account that owns the pet.</p>
          <details className="msgbox">
            <summary className="mono" style={{ fontSize: 12, cursor: "pointer", color: "var(--text-2)" }}>The exact message you’ll sign</summary>
            <div className="term" style={{ marginTop: 10 }}><pre><b>{pairMessage(pet ?? asked, device)}</b></pre><span className="c">recipient: {VAULT_ID || "—"} · nonce: 32 fresh random bytes</span></div>
          </details>
          <div className="actions" style={{ marginTop: 22 }}>
            <button type="button" className="btn solid" onClick={approve} disabled={state !== "ready" || !pet || !device} aria-busy={state === "signing"}>
              {state === "signing" ? <><span className="spin" />Approve in your wallet…</> : "Approve pairing"}
            </button>
          </div>
          {state === "signing" && <p className="note" role="status">Your wallet has the message. Nothing is sent until you sign it there.</p>}
        </>
      )}
      {state === "badlink" && <div className="bad" role="alert" style={{ marginTop: 18 }}>This link is missing the pet or the device key. Open it from the {PRODUCT} menu: Settings → Phone and Mac → Pair this Mac with my pet.</div>}
      {state === "unknown" && <div className="bad" role="alert" style={{ marginTop: 18 }}><span>No pet called “{asked}” is registered. Register it first on <Link href="/pet">Get your pet</Link>.</span></div>}
      {message && <div className="bad" role="alert" style={{ marginTop: 18 }}>{message}</div>}
    </div>
  );
}
