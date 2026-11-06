"use client";

import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { isAddress, type Address } from "viem";
import { ApiError, registerPet, worldSign } from "@/lib/api";
import { connectWallet } from "@/lib/chain";
import { PetSmall } from "@/components/PetArt";
import { txLink, WORLD_APP_ID, WORLD_ENV, WORLD_PRESET, WORLD_RP_ID } from "@/lib/config";

type Phase =
  | { kind: "form" }
  | { kind: "scan"; uri: string }
  | { kind: "registering" }
  | { kind: "done"; name: string; txHash?: string }
  | { kind: "denied" }
  | { kind: "error"; message: string };

const ACTION = "register-pet";

export default function GetYourPet() {
  const [owner, setOwner] = useState<Address | null>(null);
  const [name, setName] = useState("mochi");
  const [petKey, setPetKey] = useState("");
  const [payout, setPayout] = useState("");
  const [phase, setPhase] = useState<Phase>({ kind: "form" });
  const [walletError, setWalletError] = useState(""); // shown next to Connect wallet
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState("");

  const fullName = `${name.trim().toLowerCase()}.notchi.eth`;

  async function onConnect() {
    setWalletError("");
    try {
      const addr = await connectWallet();
      setOwner(addr);
      if (!payout) setPayout(addr);
    } catch (e) {
      setWalletError((e as Error).message);
    }
  }

  function validate(): string {
    if (!owner) return "Connect your wallet first.";
    if (!/^[a-z0-9-]{2,24}$/.test(name.trim().toLowerCase())) return "Name: 2-24 letters, numbers or dashes.";
    if (!isAddress(payout)) return "Payout address isn't a valid address.";
    if (petKey && !isAddress(petKey)) return "Pet key isn't a valid address.";
    if (!WORLD_APP_ID || !WORLD_RP_ID) return "World app ID / RP ID missing in .env.";
    return "";
  }

  async function onVerify() {
    const err = validate();
    setFormError(err);
    if (err || !owner) return;
    setBusy(true);
    try {
      const sig = await worldSign(ACTION);
      const { IDKit, orbLegacy, deviceLegacy } = await import("@worldcoin/idkit-core");
      const preset = WORLD_PRESET === "device" ? deviceLegacy({ signal: owner }) : orbLegacy({ signal: owner });
      const request = await IDKit.request({
        app_id: WORLD_APP_ID as `app_${string}`,
        action: ACTION,
        rp_context: {
          rp_id: WORLD_RP_ID,
          nonce: sig.nonce,
          created_at: Number(sig.created_at),
          expires_at: Number(sig.expires_at),
          signature: sig.sig,
        },
        allow_legacy_proofs: false,
        environment: WORLD_ENV,
      } as Parameters<typeof IDKit.request>[0]).preset(preset);

      setPhase({ kind: "scan", uri: request.connectorURI });
      const completion = await request.pollUntilCompletion({ pollInterval: 2000, timeout: 180_000 });
      if (!completion.success) {
        setPhase({ kind: "error", message: `World ID didn't complete: ${String(completion.error ?? "cancelled")}` });
        return;
      }

      setPhase({ kind: "registering" });
      const res = await registerPet({
        name: fullName,
        petKey: petKey || payout,
        ownerAddress: owner,
        payoutAddress: payout,
        worldProof: completion.result,
      });
      setPhase({ kind: "done", name: res.name ?? fullName, txHash: res.txHash });
    } catch (e) {
      if (e instanceof ApiError && e.status === 409 && e.message === "already has a pet") setPhase({ kind: "denied" });
      else setPhase({ kind: "error", message: (e as Error).message });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div className="steps">
        <span className={phase.kind === "form" ? "on" : ""}>1. Details</span>
        <span>›</span>
        <span className={phase.kind === "scan" ? "on" : ""}>2. Prove you're human</span>
        <span>›</span>
        <span className={phase.kind === "done" ? "on" : ""}>3. Move in</span>
      </div>
      <h1>Get your pet</h1>
      <p className="lead">One person, one pet. That stops fake views, so brands only pay real people.</p>

      {phase.kind === "form" && (
        <div className="card">
          {!owner ? (
            <>
              <button onClick={onConnect}>Connect wallet</button>
              {walletError && <p className="bad">{walletError}</p>}
            </>
          ) : (
            <p className="muted">
              Connected: <span className="mono">{owner}</span>
            </p>
          )}

          <label>Pet name</label>
          <input value={name} onChange={(e) => setName(e.target.value)} />
          <p className="muted mono">{fullName}</p>

          <label>Payout address</label>
          <input className="mono" value={payout} onChange={(e) => setPayout(e.target.value)} placeholder="0x..." />
          <p className="hint">Where the pet's earnings go. Only you can change it later.</p>

          <label>Pet key (optional)</label>
          <input className="mono" value={petKey} onChange={(e) => setPetKey(e.target.value)} placeholder="0x..." />
          <p className="hint">Leave empty to use the payout address.</p>

          {formError && <p className="bad">{formError}</p>}
          <p>
            <button onClick={onVerify} disabled={busy || !owner}>
              {busy ? "Starting…" : "Prove you're a real person"}
            </button>
          </p>
          {!owner && <p className="hint">Connect your wallet first.</p>}
        </div>
      )}

      {phase.kind === "scan" && (
        <div className="card">
          <h2>{WORLD_ENV === "staging" ? "Verify with the World ID simulator" : "Scan with World App"}</h2>
          {WORLD_ENV === "staging" ? (
            <p className="muted">
              Test mode: open{" "}
              <a href="https://simulator.worldcoin.org" target="_blank" rel="noreferrer">
                simulator.worldcoin.org
              </a>
              , then scan this code or paste the link below into it.
            </p>
          ) : (
            <p className="muted">Open World App and scan this code.</p>
          )}
          <div className="qr">
            <QRCodeSVG value={phase.uri} size={220} />
          </div>
          <p style={{ textAlign: "center" }}>
            <button className="ghost" onClick={() => navigator.clipboard?.writeText(phase.uri)}>
              Copy link
            </button>
          </p>
          <p className="muted" style={{ textAlign: "center" }}>
            Waiting for your phone…
          </p>
        </div>
      )}

      {phase.kind === "registering" && (
        <div className="card">
          <p>Verified. Checking the proof on our server and registering your pet onchain…</p>
        </div>
      )}

      {phase.kind === "done" && (
        <div className="card">
          <PetSmall />
          <h2 style={{ textAlign: "center" }}>{phase.name} is moving into your notch.</h2>
          {phase.txHash ? (
            <p className="muted" style={{ textAlign: "center" }}>
              Registered onchain:{" "}
              <a className="mono" href={txLink(phase.txHash)} target="_blank" rel="noreferrer">
                {phase.txHash}
              </a>
            </p>
          ) : (
            <p className="muted" style={{ textAlign: "center" }}>
              Registered.
            </p>
          )}
        </div>
      )}

      {phase.kind === "denied" && (
        <div className="card denied">
          <h2>You already have a pet.</h2>
          <p className="muted">
            World ID says this person has registered a pet before. Each human gets one, which is how brands know every
            impression comes from a real screen.
          </p>
          <button className="ghost" onClick={() => setPhase({ kind: "form" })}>
            Back
          </button>
        </div>
      )}

      {phase.kind === "error" && (
        <div className="card">
          <p className="bad">{phase.message}</p>
          <button className="ghost" onClick={() => setPhase({ kind: "form" })}>
            Try again
          </button>
        </div>
      )}
    </>
  );
}
