import Link from "next/link";
import { NotchPet } from "@/components/PetArt";

export default function Home() {
  return (
    <>
      <NotchPet />
      <span className="pill">ETHGlobal Mumbai build</span>
      <h1>Your coding agent makes you wait. Notchi makes that wait pay for itself.</h1>
      <p className="lead">
        A tiny pet lives behind a door in your MacBook notch. When Claude Code starts working, it drops out and holds up one
        short line from a sponsor. Brands pay per real impression. The pet uses what it earns to pay for its own AI brain on 0G.
      </p>
      <div className="row audiences">
        <div className="card">
          <h2>Developers</h2>
          <p className="muted">Prove you are a real person once, name your pet, and it moves into your notch.</p>
          <Link href="/pet" className="button">
            Get your pet
          </Link>
        </div>
        <div className="card">
          <h2>Brands</h2>
          <p className="muted">The pet writes three lines for you. Pick one, fund it, and any unspent budget comes back.</p>
          <Link href="/brand" className="button">
            Fund a campaign
          </Link>
        </div>
      </div>
    </>
  );
}
