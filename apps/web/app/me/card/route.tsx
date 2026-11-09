import { ImageResponse } from "next/og";
import { formatEther } from "viem";
import { SERVER_URL } from "@/lib/config";
import type { PetPublic } from "@/lib/api";

// The weekly recap card, drawn from the server's real numbers. No numbers, no card: a missing pet gets a 404.
export async function GET(req: Request) {
  const name = new URL(req.url).searchParams.get("pet")?.slice(0, 80);
  if (!name) return new Response("pet is required", { status: 400 });
  const res = await fetch(`${SERVER_URL}/pets/${encodeURIComponent(name)}`, { cache: "no-store" }).catch(() => null);
  if (!res?.ok) return new Response("unknown pet", { status: 404 });
  const p = (await res.json()) as PetPublic;
  const week = `${Number(formatEther(BigInt(p.week.wei))).toFixed(4)} 0G`;
  const rows: [string, string][] = [
    ["this week", `${week} · ${p.week.views} views`],
    ["level", p.level === null ? "?" : String(p.level)],
    ["streak", `${p.streak} day${p.streak === 1 ? "" : "s"}`],
  ];
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", justifyContent: "space-between", padding: 72, background: "#F4F2ED", color: "#0B0B0B", fontFamily: "sans-serif" }}>
        <div style={{ display: "flex", fontSize: 32, letterSpacing: 2 }}>NOTCHI{p.seeded ? " · SEEDED, NOT REAL 0G" : ""}</div>
        <div style={{ display: "flex", fontSize: 84, fontWeight: 700, lineHeight: 1 }}>{p.name}</div>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          {rows.map(([k, v]) => (
            <div key={k} style={{ display: "flex", fontSize: 44 }}>
              <span style={{ width: 260, color: "#6b6b6b" }}>{k}</span>
              <span style={{ fontWeight: 700 }}>{v}</span>
            </div>
          ))}
        </div>
        <div style={{ display: "flex", fontSize: 28, color: "#FF5A3C" }}>Earned from sponsored hooks while a coding agent worked. Paid on the 0G chain.</div>
      </div>
    ),
    { width: 1200, height: 630 },
  );
}
