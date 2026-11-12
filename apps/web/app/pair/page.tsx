"use client";

import { useEffect, useState } from "react";
import { ApiError, getPet, pairDevice } from "@/lib/api";
import { connectWallet, signOwnerMessage } from "@/lib/chain";
import { PRODUCT } from "@/lib/config";
import { PetSmall } from "@/components/PetArt";

/** Same id the server derives: first 16 hex chars of SHA-256 over the raw public key. */
async function keyId(b64u: string) {
  const raw = Uint8Array.from(atob(b64u.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", raw));
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("").slice(0, 16);
}

export default function Pair() {
  const [pet, setPet] = useState<string | null>(null);
  const [key, setKey] = useState("");
  const [device, setDevice] = useState("");
  const [account, setAccount] = useState<string | null>(null);
  const [state, setState] = useState<"loading" | "ready" | "signing" | "done" | "error">("loading");
  const [message, setMessage] = useState("");

  useEffect(() => {
    const q = new URLSearchParams(window.location.search);
    const name = q.get("pet"), k = q.get("key");
    if (!name || !k || !/^[A-Za-z0-9_-]{80,100}$/.test(k)) {
      setState("error");
      setMessage(`This link is missing the pet or the device key. Open it from the ${PRODUCT} menu: Settings → Pair this Mac with my pet.`);
      return;
    }
    setKey(k);
    Promise.all([getPet(name), keyId(k)])
      .then(([p, id]) => { setPet(p.name); setDevice(id); setState("ready"); })
      .catch((e) => { setState("error"); setMessage(e instanceof ApiError && e.status === 404 ? `No pet called "${name}" is registered. Register it first on Get your pet.` : (e as Error).message); });
  }, []);

  async function approve() {
    setMessage("");
    try {
      const a = account ?? (await connectWallet());
      setAccount(a);
      setState("signing");
      // must match the server's pairMessage exactly
      const signed = await signOwnerMessage(a, `Pair this device to my pet.\nPet: ${pet}\nDevice: ${device}`);
      await pairDevice(pet!, key, signed);
      setState("done");
    } catch (e) {
      setState("ready");
      setMessage(e instanceof ApiError && e.status === 403 ? "This NEAR account isn't the pet's owner, or the key isn't a full-access key. Connect the account that registered the pet." : (e as Error).message.split("\n")[0]);
    }
  }

  return (
    <div className="narrow">
      <p className="mono section-kicker">Pair a Mac</p>
      <h1>{state === "done" ? "This Mac is paired." : "Pair this Mac with your pet"}</h1>
      {state === "loading" && <p className="muted" role="status">Checking the link…</p>}
      {state === "error" && <p className="bad" role="alert">{message}</p>}
      {(state === "ready" || state === "signing") && (
        <div className="card">
          <PetSmall />
          <dl className="receipt">
            <div><dt>Pet</dt><dd>{pet}</dd></div>
            <div><dt>Device</dt><dd className="mono">{device}</dd></div>
          </dl>
          <p className="muted">Pairing lets this Mac's Secure Enclave sign your pet's views and clicks, so nobody else can earn as your pet. You sign one message (NEP-413) with the NEAR account that owns the pet; no transaction, no fee.</p>
          {message && <p className="bad" role="alert">{message}</p>}
          <button onClick={approve} disabled={state === "signing"} aria-busy={state === "signing"}>{state === "signing" ? "Approve in your wallet…" : "Approve pairing"}</button>
        </div>
      )}
      {state === "done" && (
        <div className="card">
          <p className="ok">Views, clicks and think calls from this Mac are now signed by its Secure Enclave.</p>
          <p className="muted">Device <span className="mono">{device}</span> paired to <strong>{pet}</strong>. You can close this tab.</p>
        </div>
      )}
    </div>
  );
}
