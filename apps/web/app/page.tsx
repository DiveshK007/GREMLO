import Link from "next/link";
import { LiveHero } from "@/components/LiveHero";
import { LiveStats } from "@/components/LiveStats";
import { NotchReveal } from "@/components/NotchReveal";
import { Reveal } from "@/components/Reveal";
import { TryHook } from "@/components/TryHook";
import { addressLink, VAULT_ADDRESS } from "@/lib/config";

export default function Home() {
  return (
    <>
      <section className="hero hero-v2">
        <div className="hero-copy">
          <p className="mono eyebrow-live"><span className="dot" /> Live on 0G Galileo testnet</p>
          <h1 className="loud">
            Your agent makes you wait.
            <span className="on-signal-type"> Notchi makes the wait pay.</span>
          </h1>
          <p className="lead">
            A tiny pet lives behind a hidden door in your MacBook notch. While your coding agent works, it walks your
            screen carrying one sponsored hook. Brands pay per verified view. You earn while you wait.
          </p>
          <p className="actions">
            <Link href="/pet" className="button">Get your pet</Link>
            <Link href="/brand" className="button ghost">Advertise to developers</Link>
          </p>
        </div>
        <LiveHero />
      </section>

      <NotchReveal />

      <Reveal className="how">
        <h2 className="section-title">How it works</h2>
        <ol className="steps-3">
          <li><span className="mono">01</span><strong>Your agent starts working</strong><p>Claude Code tells Notchi. The door in your notch opens and the pet drops out.</p></li>
          <li><span className="mono">02</span><strong>It carries one hook</strong><p>A brand's line scrolls across its sign. Hover to pause, click to open it. Never during an approval.</p></li>
          <li><span className="mono">03</span><strong>Real views get paid</strong><p>Views settle onchain to your pet's wallet. One human, one pet, verified with World ID.</p></li>
        </ol>
      </Reveal>

      <Reveal className="try-section">
        <div>
          <p className="mono section-kicker">Try it</p>
          <h2 className="section-title">Type your product. Watch the pet pitch it.</h2>
          <p className="muted">One real call to 0G. Hooks may only use claims you give us, and never promise returns.</p>
        </div>
        <TryHook />
      </Reveal>

      <Reveal className="stats-section">
        <p className="mono section-kicker">Live from the chain</p>
        <LiveStats />
        {VAULT_ADDRESS && (
          <p className="muted small">
            Read from the <a href={addressLink(VAULT_ADDRESS)} target="_blank" rel="noreferrer">campaign contract</a>'s own events. These numbers only grow with real use.
          </p>
        )}
      </Reveal>

      <Reveal className="split">
        <div className="split-half">
          <p className="mono section-kicker">Developers</p>
          <h3>Earn while your agent thinks.</h3>
          <p>A pet that tells you when the agent needs approval or is done, and gets paid for the minutes you were waiting anyway. Sponsored hooks are opt-in, with focus mode and quiet hours.</p>
          <Link href="/pet" className="button">Get your pet</Link>
        </div>
        <div className="split-half ink">
          <p className="mono section-kicker">Brands</p>
          <h3>Reach developers who block every banner.</h3>
          <p>Notchi writes 16 hooks in 8 formats on 0G. Pick 3 to 5; the pet rotates them and favours the ones developers click. Pay only for verified views; unspent budget comes back.</p>
          <Link href="/brand" className="button">Fund a campaign</Link>
        </div>
      </Reveal>

      <Reveal className="demo">
        <video src="/demo.mp4" autoPlay muted loop playsInline preload="none" aria-label="Notchi dropping out of the notch while the agent works" />
      </Reveal>

      <section className="band">
        <p className="dsp">Put your hook on the sign.</p>
        <p className="band-copy">The pet is a Mac app that reacts to Claude Code. Every payment here is a real testnet transaction.</p>
        <Link href="/brand" className="button">Fund a campaign</Link>
      </section>
    </>
  );
}
