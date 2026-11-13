import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";
import { formatNear, PRODUCT, SERVER_URL } from "@/lib/config";
import type { PetPublic } from "@/lib/api";
import { knownSpecies, speciesOf } from "@/lib/species";

// The weekly share card, 1200x630, dark only: a social card can't know the viewer's theme (APP_PAGES_REDESIGN §4.3).
// Drawn from the server's real numbers; a missing pet is a 404, never a card. next/og (Satori) takes flexbox and inline
// styles only, so the pet is a pre-cut still per species and the fonts are loaded here.

const pub = (p: string) => join(process.cwd(), "public", p);
let fonts: Promise<Buffer[]> | null = null;
const loadFonts = () => (fonts ??= Promise.all(["BricolageGrotesque-ExtraBold", "Inter-Medium", "JetBrainsMono-Medium"].map((f) => readFile(pub(`fonts/${f}.woff`)))));

export async function GET(req: Request) {
  const name = new URL(req.url).searchParams.get("pet")?.slice(0, 80);
  if (!name) return new Response("pet is required", { status: 400 });
  const res = await fetch(`${SERVER_URL}/pets/${encodeURIComponent(name)}`, { cache: "no-store" }).catch(() => null);
  if (!res) return new Response("server unreachable", { status: 502 });
  if (res.status === 404) return new Response("unknown pet", { status: 404 });
  if (!res.ok) return new Response("server error", { status: 502 });
  const p = (await res.json()) as PetPublic;

  // unknown values are a dash, never a zero or "?"; earnings show 4 decimals and no unit
  const known = knownSpecies(p.species);
  const sp = speciesOf(p.species);
  const week = p.week?.wei != null ? Number(formatNear(BigInt(p.week.wei))).toFixed(4) : "—";
  const level = p.level != null ? String(p.level) : "—";
  const streak = p.streak != null ? `${p.streak} day${p.streak === 1 ? "" : "s"}` : "—";
  const stage = p.stage ? p.stage[0].toUpperCase() + p.stage.slice(1) : "";
  const [brico, inter, mono] = await loadFonts();
  const still = `data:image/png;base64,${(await readFile(pub(`pets/stills/${sp.id}-celebrate.png`))).toString("base64")}`;
  // every family needs a generic fallback, or the renderer falls back to a serif
  const D = "'Bricolage Grotesque', Inter, sans-serif", M = "'JetBrains Mono', monospace";
  const stat = (k: string, v: string, sub?: string) => (
    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ fontFamily: M, fontSize: 15, letterSpacing: ".12em", textTransform: "uppercase", color: "rgba(244,242,237,.5)" }}>{k}</div>
      <div style={{ fontFamily: D, fontSize: 54, letterSpacing: "-.03em", color: "#F4F2ED" }}>{v}</div>
      {sub ? <div style={{ fontSize: 17, color: "rgba(244,242,237,.62)" }}>{sub}</div> : null}
    </div>
  );

  return new ImageResponse(
    (
      <div style={{ width: 1200, height: 630, display: "flex", background: "#0B0B0B", color: "#F4F2ED", fontFamily: "Inter, sans-serif" }}>
        <div style={{ width: 720, display: "flex", flexDirection: "column", justifyContent: "space-between", padding: "56px 0 52px 64px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <div style={{ width: 16, height: 16, borderRadius: 8, background: sp.accent }} />
            <div style={{ fontFamily: D, fontSize: 30, letterSpacing: "-.02em" }}>{PRODUCT}</div>
            {p.seeded ? (
              <div style={{ marginLeft: 10, fontFamily: M, fontSize: 15, letterSpacing: ".1em", textTransform: "uppercase", color: "#0B0B0B", background: "#F4F2ED", padding: "8px 10px", borderRadius: 6 }}>
                Seeded · not real money
              </div>
            ) : null}
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <div style={{ fontFamily: M, fontSize: 17, letterSpacing: ".14em", textTransform: "uppercase", color: sp.accent }}>
              {`${known ? sp.name : `${PRODUCT} pet`}${stage ? ` · ${stage}` : ""}`}
            </div>
            <div style={{ fontFamily: D, fontSize: p.name.length > 14 ? 92 : 168, lineHeight: 0.88, letterSpacing: "-.045em" }}>{p.name}</div>
          </div>
          <div style={{ display: "flex", gap: 56 }}>
            {stat("This week", week, `${p.week?.views ?? 0} views`)}
            {stat("Level", level)}
            {stat("Streak", streak)}
          </div>
          <div style={{ fontSize: 19, color: "rgba(244,242,237,.72)" }}>Earned from sponsored lines while a coding agent worked.</div>
        </div>
        <div style={{ flex: 1, display: "flex", position: "relative", alignItems: "flex-end", justifyContent: "center", background: "#141414" }}>
          <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 420, display: "flex", backgroundImage: `radial-gradient(circle at 50% 100%, ${sp.accent}66, transparent 70%)` }} />
          <div style={{ position: "absolute", top: 0, left: 130, width: 220, height: 40, background: "#000", borderRadius: "0 0 18px 18px" }} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={still} width={384} height={416} style={{ marginBottom: 34 }} alt="" />
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
      fonts: [
        { name: "Bricolage Grotesque", data: brico, weight: 800 },
        { name: "Inter", data: inter, weight: 500 },
        { name: "JetBrains Mono", data: mono, weight: 500 },
      ],
    },
  );
}
