"use client";

import { useEffect, useState } from "react";
import { SERVER_URL } from "@/lib/config";

type Species = { id: string; name: string; creator: string; rows: number; at: number };

// R2 §13: community species, reviewed by two people who play every row. Creators get credit; nothing is sold.
export default function Gallery() {
  const [list, setList] = useState<Species[] | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    fetch(`${SERVER_URL}/gallery`).then((r) => r.json()).then((b) => setList(b.species ?? [])).catch(() => setError("Can't reach the gallery right now."));
  }, []);
  return (
    <main>
      <h1>Community species</h1>
      <p className="muted">Pets drawn by the community. Each one passed machine checks and two human reviewers. Only reviewed species can hold a sponsored line.</p>
      {error && <p className="error">{error}</p>}
      {list && list.length === 0 && <p className="muted">None listed yet.</p>}
      <ul className="gallery">
        {list?.map((s) => (
          <li key={s.id}><strong>{s.name}</strong> <span className="muted">by {s.creator}</span></li>
        ))}
      </ul>
      <section className="card">
        <h2>Make one</h2>
        <pre className="mono">{`notchi new my-pet
notchi validate my-pet
notchi preview my-pet
notchi submit my-pet --creator "your name"`}</pre>
        <p className="muted">Only art you made. Imports from other pet apps stay on your Mac as companions.</p>
      </section>
    </main>
  );
}
