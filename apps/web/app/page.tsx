import Link from "next/link";
import { LiveSign } from "@/components/LiveSign";
import { addressLink, VAULT_ADDRESS } from "@/lib/config";

export default function Home() {
  return (
    <>
      <section className="hero">
        <div>
          <h1 className="loud">
            Your agent makes you wait.
            <span className="on-signal-type"> Notchi makes the wait pay.</span>
          </h1>
          <p className="lead">
            A small pet lives behind a hidden door in your MacBook notch. While Claude Code works, it holds up one sponsored
            line. Brands pay per real impression, and the pet spends what it earns on its own 0G brain.
          </p>
          <p className="actions">
            <Link href="/pet" className="button">
              Get your pet
            </Link>
            <Link href="/brand" className="button ghost">
              Fund a campaign
            </Link>
          </p>
        </div>
        <LiveSign />
      </section>

      <ul className="stats">
        <li>
          <span className="mono">Chain</span>0G Galileo testnet
        </li>
        <li>
          <span className="mono">Brain</span>0G Compute
        </li>
        <li>
          <span className="mono">Humans</span>World ID, one pet each
        </li>
        <li>
          <span className="mono">Contract</span>
          {VAULT_ADDRESS ? (
            <a className="mono" href={addressLink(VAULT_ADDRESS)} target="_blank" rel="noreferrer">
              {VAULT_ADDRESS.slice(0, 6)}…{VAULT_ADDRESS.slice(-4)}
            </a>
          ) : (
            "–"
          )}
        </li>
      </ul>

      <section className="band">
        <p className="dsp">Put your line on the sign.</p>
        <p className="band-copy">The pet is a Mac app that reacts to Claude Code. Every payment here is a real testnet transaction.</p>
        <Link href="/brand" className="button">
          Fund a campaign
        </Link>
      </section>
    </>
  );
}
