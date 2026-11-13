"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { QRCodeSVG } from "qrcode.react";
import { ApiError, nameFree, registerPet, worldSign } from "@/lib/api";
import { connectWallet } from "@/lib/chain";
import { txLink, WORLD_APP_ID, WORLD_ENV, WORLD_PRESET, WORLD_RP_ID } from "@/lib/config";
import { Pet } from "@/components/Pet";
import { toast, useNotch } from "@/components/Shell";
import { cleanPetName, nameCandidates, validPetName } from "@/lib/petname";
import "./pet.css";

type Phase =
  | { kind: "form" }
  | { kind: "scan"; uri: string; until: number }
  | { kind: "registering" }
  | { kind: "done"; name: string; txHash?: string; verifyTx?: string; at: number }
  | { kind: "denied" }
  | { kind: "error"; title: string; message: string };

const ACTION = "register-pet";
const SCAN_MS = 180_000; // how long IDKit waits for the phone
// NEAR account id rules: 2-64 chars, lowercase parts joined by "." with "-" or "_" inside a part
const isAccountId = (v: string) => v.length >= 2 && v.length <= 64 && /^(([a-z\d]+[-_])*[a-z\d]+\.)*([a-z\d]+[-_])*[a-z\d]+$/.test(v);
const STEPS = ["Details", "Prove you’re human", "Move in"];

function Steps({ at }: { at: number | null }) {
  return (
    <ol className="steps" aria-label="Progress">
      {STEPS.map((t, i) => <li key={t} aria-current={at === i ? "step" : undefined} className={at != null && i < at ? "done" : undefined}>{t}</li>)}
    </ol>
  );
}

function Egg({ frames = [0, 0, 0, 1, 0, 2] }: { frames?: number[] }) {
  return (
    <div className="stage" style={{ minHeight: 420, flexDirection: "column", justifyContent: "flex-end", alignItems: "center", paddingBottom: 54 }}>
      <span className="mini-notch" aria-hidden="true" />
      <Pet row="hatch" frames={frames} fps={3} scale={1} />
      <div className="cap mono faint" style={{ fontSize: 11.5, right: 16, textAlign: "center" }}>
        Your egg hatches on your Mac the first time your agent works.<br />You find out the species then.
      </div>
    </div>
  );
}

function Countdown({ until }: { until: number }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t); }, []);
  const s = Math.max(0, Math.round((until - now) / 1000));
  return <span className="timer">Code expires in {Math.floor(s / 60)}:{String(s % 60).padStart(2, "0")}</span>;
}

export default function GetYourPet() {
  const notch = useNotch();
  const [owner, setOwner] = useState<string | null>(null);
  const [name, setName] = useState("mochi");
  const [payout, setPayout] = useState("");
  const [phase, setPhase] = useState<Phase>({ kind: "form" });
  const [walletError, setWalletError] = useState("");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState("");
  const [taken, setTaken] = useState<string[] | null>(null); // free suggestions when the name is taken
  const [movedIn, setMovedIn] = useState(""); // formatted in the browser (hydration)

  useEffect(() => {
    if (phase.kind === "scan") notch.set("wait", "waiting for your phone");
    else if (phase.kind === "registering") notch.base("egg");
    else if (phase.kind === "done") { notch.base("door"); setMovedIn(new Intl.DateTimeFormat("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" }).format(phase.at)); }
    else notch.base("rest");
  }, [phase, notch]);

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
    if (!validPetName(name)) return "Name: 2-24 letters, numbers or dashes, not starting or ending with a dash.";
    if (!isAccountId(payout.trim())) return "Payout must be an account id, like mochi.testnet.";
    if (!WORLD_APP_ID || !WORLD_RP_ID) return "World app ID / RP ID missing in .env.";
    return "";
  }

  /** The next two free numeric suffixes (mochi-2, mochi-3…). Names are free and never auctioned (R4 §18). */
  async function suggestions(base: string) {
    const out: string[] = [];
    for (const s of nameCandidates(base)) {
      if (out.length >= 2) break;
      if (await nameFree(s).catch(() => false)) out.push(s);
    }
    return out;
  }

  async function onVerify() {
    const err = validate();
    setFormError(err);
    setTaken(null);
    if (err || !owner) return;
    setBusy(true);
    notch.set("think");
    try {
      // check the name before the scan, so nobody proves they're human only to hear it's taken
      if (!(await nameFree(name))) { setTaken(await suggestions(name)); notch.base("rest"); return; }
      const sig = await worldSign(ACTION);
      const { IDKit, orbLegacy, deviceLegacy } = await import("@worldcoin/idkit-core");
      const preset = WORLD_PRESET === "device" ? deviceLegacy({ signal: owner }) : orbLegacy({ signal: owner });
      const request = await IDKit.request({
        app_id: WORLD_APP_ID as `app_${string}`,
        action: ACTION,
        rp_context: { rp_id: WORLD_RP_ID, nonce: sig.nonce, created_at: Number(sig.created_at), expires_at: Number(sig.expires_at), signature: sig.sig },
        allow_legacy_proofs: false,
        environment: WORLD_ENV,
      } as Parameters<typeof IDKit.request>[0]).preset(preset);

      setPhase({ kind: "scan", uri: request.connectorURI, until: Date.now() + SCAN_MS });
      const completion = await request.pollUntilCompletion({ pollInterval: 2000, timeout: SCAN_MS });
      if (!completion.success) {
        setPhase({ kind: "error", title: "World ID didn’t finish.", message: `World ID didn't complete: ${String(completion.error ?? "cancelled")}` });
        return;
      }
      setPhase({ kind: "registering" });
      const res = await registerPet({ name, owner, payout: payout.trim(), worldProof: completion.result });
      setPhase({ kind: "done", name: res.name ?? name, txHash: res.txHash, verifyTx: res.verifyTx, at: Date.now() });
    } catch (e) {
      const msg = (e as Error).message;
      if (e instanceof ApiError && e.status === 409 && msg === "already has a pet") setPhase({ kind: "denied" });
      else if (e instanceof ApiError && e.status === 409 && msg === "pet already registered") { setPhase({ kind: "form" }); setTaken(await suggestions(name)); }
      else if (e instanceof ApiError && e.status === 0) setPhase({ kind: "error", title: "We couldn’t reach the server.", message: msg });
      else if (/World proof rejected/.test(msg)) setPhase({ kind: "error", title: "World ID didn’t accept that proof.", message: msg });
      else setPhase({ kind: "error", title: "That didn’t work.", message: msg });
    } finally {
      setBusy(false);
    }
  }

  const head = (
    <div className="wrap">
      <div className="sec-head">
        <div>
          <div className="eyebrow">Get your pet</div>
          <h1 className="dsp"><span style={{ whiteSpace: "nowrap" }}>One human.</span><br /><span style={{ whiteSpace: "nowrap" }}>One pet.</span></h1>
        </div>
        <p>That stops fake views, so brands only pay real people. Prove you’re a person once with World ID, name your pet, and it moves into your notch.</p>
      </div>
    </div>
  );

  let body: React.ReactNode;
  if (phase.kind === "form") {
    const bad = !!taken || formError.startsWith("Name");
    body = (
      <div className="pet-grid">
        <div className="panel">
          <Steps at={0} />
          <div style={{ height: 28 }} />
          <div className="wallet-row">
            {owner ? (
              <><span className="pill"><i />Connected</span><span className="acct">{owner}</span><button type="button" className="link" onClick={onConnect}>Change</button></>
            ) : (
              <><button type="button" className="btn ghost sm" onClick={onConnect}>Connect wallet</button><p>The account that will own the pet. You sign once, later.</p></>
            )}
          </div>
          {walletError && <div className="bad" role="alert">{walletError}</div>}
          <div className="field" data-invalid={bad || undefined}>
            <label htmlFor="nm">Pet name</label>
            <input id="nm" className="big" value={name} autoComplete="off" spellCheck={false} maxLength={24} aria-describedby="nmh" aria-invalid={bad || undefined}
              onChange={(e) => { setName(cleanPetName(e.target.value)); setTaken(null); }} />
            <span className="echo" aria-hidden="true">{name}</span>
            {taken ? (
              <>
                <div className="bad" role="alert" id="nmh">{name} is taken.</div>
                <div className="suggest">
                  {taken.length > 0 && <span className="faint" style={{ fontSize: 13 }}>Try</span>}
                  {taken.map((s) => <button key={s} type="button" className="chipbtn" onClick={() => { setName(s); setTaken(null); }}>{s}</button>)}
                  <span className="faint" style={{ fontSize: 13 }}>{taken.length ? "or pick another name." : "Pick another name."} Names are free, never auctioned.</span>
                </div>
              </>
            ) : (
              <p className="hint" id="nmh">2–24 lowercase letters, numbers or dashes. It becomes the pet’s address.</p>
            )}
          </div>
          <div className="field">
            <label htmlFor="po">Payout account</label>
            <input id="po" value={payout} onChange={(e) => setPayout(e.target.value)} placeholder="mochi.testnet" autoComplete="off" spellCheck={false} aria-describedby="poh" />
            <p className="hint" id="poh">The account the pet’s earnings go to. It must already exist. Only you can change it later.</p>
          </div>
          <div className="actions" style={{ marginTop: 8 }}>
            <button type="button" className="btn solid" onClick={onVerify} disabled={busy || !owner} aria-busy={busy} aria-describedby={owner ? undefined : "why"}>
              {busy ? <><span className="spin" />Starting…</> : "Prove you’re a real person"}
            </button>
          </div>
          {!owner && <p className="note" id="why">Connect your wallet first.</p>}
          {formError && <div className="bad" role="alert">{formError}</div>}
        </div>
        <Egg />
      </div>
    );
  } else if (phase.kind === "scan") {
    const staging = WORLD_ENV === "staging";
    body = (
      <div className="pet-grid">
        <div className="panel">
          <Steps at={1} />
          <div style={{ height: 28 }} />
          <div className="scan">
            <div className="qr" role="img" aria-label="QR code for World ID"><QRCodeSVG value={phase.uri} size={220} /></div>
            <div>
              {staging ? <span className="pill warn"><i />Test mode</span> : <span className="eyebrow">Prove you’re human</span>}
              <h2>{staging ? "Verify with the World ID simulator" : "Scan with World App"}</h2>
              <p>
                {staging
                  ? <>Test mode: open <a href="https://simulator.worldcoin.org" target="_blank" rel="noreferrer">simulator.worldcoin.org</a>, then scan this code or paste the link below into it.</>
                  : "Open World App and scan this code."}
              </p>
              <div className="actions">
                <button type="button" className="btn ghost sm" onClick={() => { void navigator.clipboard?.writeText(phase.uri); toast("Link copied"); }}>Copy link</button>
              </div>
              <p className="note" role="status" style={{ marginTop: 22 }}><span className="spin" aria-hidden="true" />Waiting for your phone…</p>
              <Countdown until={phase.until} />
            </div>
          </div>
        </div>
        <Egg frames={[0, 1, 0, 2]} />
      </div>
    );
  } else if (phase.kind === "registering") {
    body = (
      <div className="panel reg" role="status">
        <Steps at={null} />
        <span className="wob"><Pet row="hatch" frames={[1, 2, 1, 2, 3]} fps={5} scale={1} /></span>
        <div className="eyebrow">Moving in</div>
        <p style={{ margin: 0, fontSize: 17, color: "var(--fg)" }}>Verified. Checking the proof on our server and registering your pet…</p>
      </div>
    );
  } else if (phase.kind === "done") {
    body = (
      <div className="done-grid">
        <div className="cert">
          <div className="ttl">Gremlo · certificate of moving in</div>
          <Pet row="hatch" frame={0} scale={0.62} />
          <div>
            <div className="dsp nm">{phase.name}</div>
            <dl><dt>Owner</dt><dd>{owner}</dd><dt>Moved in</dt><dd>{movedIn || "today"}</dd><dt>Species</dt><dd>hatches on your Mac</dd><dt>First agent</dt><dd>—</dd></dl>
          </div>
          <div className="stamp">one human<br />one pet</div>
          <div className="ex2">“First agent” fills in when your Mac reports one.</div>
        </div>
        <div>
          <div className="eyebrow">Step 3 · Move in</div>
          <h2 className="dsp">{phase.name} is moving into your notch.</h2>
          <div className="proofs">
            {phase.txHash || phase.verifyTx ? (
              <>
                {phase.txHash && <div><span>Registered</span><a className="hash" href={txLink(phase.txHash)} target="_blank" rel="noreferrer">{phase.txHash}</a></div>}
                {phase.verifyTx && <div><span>Marked verified</span><a className="hash" href={txLink(phase.verifyTx)} target="_blank" rel="noreferrer">{phase.verifyTx}</a></div>}
              </>
            ) : <div>Registered.</div>}
          </div>
          <p className="muted" style={{ margin: "0 0 12px" }}>Open the Gremlo app on your Mac. The egg is waiting in the notch and hatches the first time your agent starts working.</p>
          <p className="note" style={{ margin: "0 0 22px" }}>One more step to earn: pair that Mac. In the Gremlo menu bar, press <b>Pair</b> and sign once with this wallet. Views only count from a paired Mac.</p>
          <div className="actions"><Link className="btn solid" href={`/me?pet=${encodeURIComponent(phase.name)}`}>See your pet</Link></div>
        </div>
      </div>
    );
  } else if (phase.kind === "denied") {
    body = (
      <div className="denied">
        <div className="one" aria-hidden="true"><b>1</b><span><Pet row="sit" fps={3} scale={0.7} /></span></div>
        <div>
          <div className="eyebrow">One human, one pet</div>
          <h2 className="dsp">You already have a pet.</h2>
          <p>World ID says this person has registered a pet before. Each human gets one, which is how brands know every impression comes from a real screen.</p>
          <div className="actions">
            <button type="button" className="btn ghost" onClick={() => setPhase({ kind: "form" })}>Back</button>
            <Link className="btn" href="/me" style={{ padding: "0 6px" }}>See your pet →</Link>
          </div>
        </div>
      </div>
    );
  } else {
    body = (
      <div className="pet-grid">
        <div className="panel">
          <Steps at={null} />
          <div style={{ height: 28 }} />
          <h2>{phase.title}</h2>
          <div className="bad" role="alert"><span className="mono" style={{ fontSize: 13.5 }}>{phase.message}</span></div>
          <p className="muted" style={{ margin: "14px 0 24px" }}>Your details are kept. Nothing was registered and nothing was charged.</p>
          <div className="actions"><button type="button" className="btn solid" onClick={() => setPhase({ kind: "form" })}>Try again</button></div>
        </div>
        <Egg frames={[0]} />
      </div>
    );
  }

  return <>{head}<div className="wrap">{body}</div></>;
}
