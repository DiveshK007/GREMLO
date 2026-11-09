"use client";

import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { formatEther, getAddress, parseEther, type Address } from "viem";
import { feedAction, ownerMessage, worldSign, type PetPublic } from "@/lib/api";
import { connectWallet, setPayout, signText } from "@/lib/chain";
import { txLink, WORLD_APP_ID, WORLD_ENV, WORLD_PRESET, WORLD_RP_ID } from "@/lib/config";

const og = (wei: string | bigint) => `${Number(formatEther(BigInt(wei))).toFixed(4)} 0G`;

/** The pet pays for its own 0G brain: opt in, see its credit and meals, and answer its requests above the cap. */
export default function Feed({ pet, reload }: { pet: PetPublic; reload: () => void }) {
  const f = pet.feed!;
  const [account, setAccount] = useState<Address | null>(null);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [note, setNote] = useState<{ text: string; tx?: string } | null>(null);
  const [cap, setCap] = useState(formatEther(BigInt(f.capWei)));
  const [scan, setScan] = useState("");

  async function run(label: string, fn: (a: Address) => Promise<{ text: string; tx?: string } | void>) {
    setError("");
    setNote(null);
    setBusy(label);
    try {
      const a = account ?? (await connectWallet());
      setAccount(a);
      const r = await fn(a);
      if (r) setNote(r);
      reload();
    } catch (e) {
      setError((e as Error).message.split("\n")[0]);
    } finally {
      setBusy("");
      setScan("");
    }
  }

  /** Signs an owner action with the connected wallet, in the exact words the server checks. */
  async function signed(a: Address, action: string, detail: string) {
    const time = Date.now();
    return { time, signature: await signText(a, ownerMessage(action, pet.name, detail, time)) };
  }

  const optIn = () => run("optin", async (a) => ({ text: "Earnings now go to your pet's wallet.", tx: await setPayout(a, getAddress(pet.petKey), getAddress(f.wallet)) }));
  const optOut = () => run("optout", async (a) => ({ text: "Earnings go to your wallet again.", tx: await setPayout(a, getAddress(pet.petKey), a) }));
  const saveCap = () => run("cap", async (a) => {
    const wei = parseEther(cap);
    await feedAction(pet.name, "cap", { cap, ...(await signed(a, "Set my Notchi pet's daily food cap", `Cap: ${formatEther(wei)} 0G`)) });
    return { text: `Daily cap set to ${formatEther(wei)} 0G.` };
  });
  const withdraw = () => run("withdraw", async (a) => {
    const r = await feedAction(pet.name, "withdraw", await signed(a, "Send my Notchi pet's wallet to me", `To: ${getAddress(a)}`));
    return { text: "Sent the pet wallet's balance to you.", tx: r.txHash };
  });

  const req = f.approval;
  const detail = req ? `Request: ${req.id}\nAmount: ${formatEther(BigInt(req.amount))} 0G` : "";
  const decline = () => run("decline", async (a) => {
    await feedAction(pet.name, "decline", { id: req!.id, ...(await signed(a, "Decline my Notchi pet's spend", detail)) });
    return { text: "Declined. It waits for tomorrow's cap." };
  });
  const approve = () => run("approve", async (a) => {
    const sig = await signed(a, "Approve my Notchi pet's spend", detail);
    const ws = await worldSign("approve-spend");
    const { IDKit, orbLegacy, deviceLegacy } = await import("@worldcoin/idkit-core");
    const preset = WORLD_PRESET === "device" ? deviceLegacy({ signal: a }) : orbLegacy({ signal: a });
    const request = await IDKit.request({
      app_id: WORLD_APP_ID as `app_${string}`,
      action: "approve-spend",
      rp_context: { rp_id: WORLD_RP_ID, nonce: ws.nonce, created_at: Number(ws.created_at), expires_at: Number(ws.expires_at), signature: ws.sig },
      allow_legacy_proofs: false,
      environment: WORLD_ENV,
    } as Parameters<typeof IDKit.request>[0]).preset(preset);
    setScan(request.connectorURI);
    const done = await request.pollUntilCompletion({ pollInterval: 2000, timeout: 180_000 });
    if (!done.success) throw new Error(`World ID didn't complete: ${String(done.error ?? "cancelled")}`);
    setScan("");
    await feedAction(pet.name, "approve", { id: req!.id, worldProof: done.result, ...sig });
    return { text: `Approved ${og(req!.amount)}. It eats on the next pass.` };
  });

  return (
    <div className="card">
      <p className="mono section-kicker">Pays for its own brain</p>
      {!f.on ? (
        <>
          <p>Let {pet.name} pay for its 0G calls from what it earns. Brands pay its own wallet; it deposits up to {og(f.capWei)} a day into the 0G Router and its next thoughts are charged from that.</p>
          <p className="muted">Pet wallet <span className="mono">{f.wallet}</span>. You can switch back or take the balance out at any time.</p>
          <button onClick={optIn} disabled={!!busy}>{busy === "optin" ? "Confirm in your wallet…" : "Let it pay for its brain"}</button>
        </>
      ) : (
        <>
          <dl className="receipt">
            <div><dt>0G credit</dt><dd>{pet.computeBalance === null ? "unknown" : og(pet.computeBalance)}</dd></div>
            <div><dt>Deposited today</dt><dd>{og(f.fedTodayWei)} of {og(f.capWei)}</dd></div>
          </dl>
          {req?.status === "pending" && (
            <div role="status">
              <p>It hit today's cap and wants {og(req.amount)} more. Approve with your wallet and World ID, or decline.</p>
              <div className="row">
                <button onClick={approve} disabled={!!busy}>{busy === "approve" ? (scan ? "Scan with World App…" : "Confirm in your wallet…") : "Approve"}</button>
                <button className="ghost" onClick={decline} disabled={!!busy}>{busy === "decline" ? "Confirm in your wallet…" : "Decline"}</button>
              </div>
              {scan && <QRCodeSVG value={scan} size={180} />}
            </div>
          )}
          {req?.status === "denied" && <p className="bad">Last approval was refused: {req.reason}</p>}
          {f.meals.length > 0 && (
            <ul className="meals">
              {[...f.meals].reverse().map((m) => (
                <li key={m.txHash}>{new Date(m.at).toLocaleString()}: {og(m.amount)} <a className="mono" href={txLink(m.txHash)} target="_blank" rel="noreferrer">{m.txHash.slice(0, 10)}…</a></li>
              ))}
            </ul>
          )}
          <form className="topup" onSubmit={(e) => { e.preventDefault(); void saveCap(); }}>
            <label htmlFor="cap">Daily cap (0G)</label>
            <input id="cap" inputMode="decimal" value={cap} onChange={(e) => setCap(e.target.value)} />
            <button type="submit" disabled={!!busy}>{busy === "cap" ? "Signing…" : "Save"}</button>
          </form>
          <div className="row">
            <button className="ghost" onClick={withdraw} disabled={!!busy}>{busy === "withdraw" ? "Signing…" : "Send its wallet to me"}</button>
            <button className="ghost" onClick={optOut} disabled={!!busy}>{busy === "optout" ? "Confirm in your wallet…" : "Pay me directly again"}</button>
          </div>
        </>
      )}
      {error && <p className="bad" role="alert">{error}</p>}
      {note && <p className="ok">{note.text} {note.tx && <a className="mono" href={txLink(note.tx)} target="_blank" rel="noreferrer">{note.tx.slice(0, 10)}…</a>}</p>}
    </div>
  );
}
