"use client";

import { useEffect, useState } from "react";
import { SpeciesSprite, ROWS } from "@/components/Species";
import { SERVER_URL } from "@/lib/config";

type ParkPet = { id: string; name: string; species: string; stage: string; outfit: string[] };

// R4 §14: opt-in, random order on every load, no ranking and no counts. Each pet shows only its name, species,
// stage and today's outfit.
export default function Park() {
  const [pets, setPets] = useState<ParkPet[] | null>(null);
  const [error, setError] = useState("");
  const [tapped, setTapped] = useState<string | null>(null);

  useEffect(() => {
    fetch(`${SERVER_URL}/park`).then((r) => r.json()).then((b) => setPets(b.pets ?? [])).catch(() => setError("Can't reach the park right now."));
  }, []);

  return (
    <main>
      <h1>The pet park</h1>
      <p className="muted">Pets whose owners chose to show them. Random order every time; nobody is ranked. Tap one to say hi.</p>
      {error && <p className="error">{error}</p>}
      {pets && pets.length === 0 && <p className="muted">Nobody is out right now.</p>}
      <div className="park">
        {pets?.map((p) => (
          <button key={p.id} className="park-pet" onClick={() => setTapped(p.id)} aria-label={`${p.name}, a ${p.stage}`}>
            <SpeciesSprite species={p.species} row={tapped === p.id ? ROWS.greet : ROWS.idle} frames={tapped === p.id ? 8 : 1} scale={0.5} />
            <strong>{p.name}</strong>
            <small className="muted">{p.stage}{p.outfit.length ? ` · ${p.outfit.join(", ")}` : ""}</small>
            {tapped === p.id && <a className="visit" href={`gremlo://visit?to=${p.id}`}>Send my pet to visit</a>}
          </button>
        ))}
      </div>
      <p className="muted">To join, turn on &quot;Show my pet in the park&quot; in the Mac app&apos;s settings. Leaving removes your pet at the next refresh.</p>
    </main>
  );
}
