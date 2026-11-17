import type { Metadata } from "next";
import Link from "next/link";
import { REVALIDATE, readLive } from "@/lib/experience";
import { istWhen, modelName, near4, shortHash, shortReq, split } from "@/lib/experience-format";
import { formatNear, txLink } from "@/lib/config";
import { CopyLine } from "./CopyLine";
import { Demo } from "./Demo";
import { Down, LiveDot, PROOF_MD, Spr, Tick } from "./parts";
import "./experience.css";

export const revalidate = REVALIDATE;

const ONE_LINE = "Gremlo is a pet in your MacBook notch that earns its own AI by holding a sponsored line while your coding agent works.";
export const metadata: Metadata = {
  title: "Gremlo · for judges",
  description: ONE_LINE,
  openGraph: { title: "Gremlo · for judges", description: ONE_LINE },
};

const CHIPS: [string, string][] = [
  ["#D97757", "Claude Code · Codex · Cursor"],
  ["#2ED3B7", "Settled on NEAR testnet"],
  ["#B48CFF", "Thinks with NEAR AI in a TEE"],
  ["#FFC93C", "One human, one pet (World ID)"],
];
const TOUR: [string, string, string][] = [
  ["#pet", "#FF5A3C", "01 · The pet"],
  ["#loop", "#FFC93C", "02 · The money loop"],
  ["#brain", "#B48CFF", "03 · The brain"],
  ["#proof", "#8FD14F", "04 · Live proof"],
  ["#status", "#4CC9FF", "05 · Built vs next"],
  ["#next", "#F4F2ED", "06 · Go deeper"],
];
const LOOP = [
  { num: "01", title: "A brand funds a campaign", body: "It writes a short line and pays into the vault contract from its own wallet.", foot: "vault.gremlo.testnet", color: "#FFC93C" },
  { num: "02", title: "The pet shows the line", body: "Only while your agent works. Clearly labelled. Never during a screen share.", foot: "Mac app · notch", color: "#FF5A3C" },
  { num: "03", title: "Your Mac signs the view", body: "5 s on screen, unlocked, visible, on a paired Mac. Signed by its Secure Enclave.", foot: "hash-chained public log", color: "#4CC9FF" },
  { num: "04", title: "Settled on NEAR", body: "The server checks the signed views and settles them in the vault.", foot: "settle_impressions", color: "#2ED3B7" },
  { num: "05", title: "You earn, the pet eats", body: "80% to the developer. 20% into the pet’s own compute budget.", foot: "compute share 20%", color: "#8FD14F" },
];
const WORKS = [
  "The vault contract on NEAR testnet: campaigns, settlements and the pet’s compute budget.",
  "The full loop ran end to end: pet registered, campaign funded, signed views settled, AI calls charged.",
  "Thoughts are NEAR AI calls in a TEE; one completion verified SIGNED against the attested key.",
  "The Mac app: notch pet, the sign, approvals before risky commands, Secure Enclave signing.",
  "A hash-chained public log of every view, replayable against the bill.",
];
const NOT_YET = [
  "Testnet only. Nothing is on mainnet.",
  "Mac only. The iPhone and Watch apps run in the simulator.",
  "Views are settled by an operator (the server) after it checks the Mac’s signatures, not by the Mac itself.",
  "The pet’s own purse contract is built and tested, but not deployed.",
  "AI calls are charged a fixed per-tier rate in NEAR, not the real USD bill.",
  "World ID ran against the simulator in the final run.",
];
const GH = "https://github.com/DiveshK007/GREMLO";
const LINKS: { tag: string; title: string; body: string; href: string; color: string; ext?: boolean }[] = [
  { tag: "LIVE", title: "Live numbers", body: "Every live number, on one page.", href: "/live", color: "#8FD14F" },
  { tag: "LIVE", title: "The pet park", body: "Pets out for a walk, right now.", href: "/park", color: "#8FD14F" },
  { tag: "LIVE", title: "A live campaign", body: "Campaign 3, as a brand sees it.", href: "/brand?c=3", color: "#8FD14F" },
  { tag: "CODE", title: "The repo", body: "Mac app, server, web and contracts.", href: GH, color: "#4CC9FF", ext: true },
  { tag: "PROOF", title: "PROOF.md", body: "Every transaction, checked and explained.", href: PROOF_MD, color: "#2ED3B7", ext: true },
  { tag: "ON A MAC", title: "Install Gremlo", body: "macOS 13+. Download from Releases.", href: `${GH}/releases`, color: "#FF5A3C", ext: true },
];
const ACTION_COLOR: Record<string, string> = { celebrate: "#8FD14F", work: "#D97757" };

const Head = ({ n, label, color, id, children, extra }: { n: string; label: string; color: string; id: string; children: React.ReactNode; extra?: React.ReactNode }) => (
  <div className="xp-head">
    <div className="xp-eyebrow-row">
      <span className="xp-eyebrow" style={{ color }}>
        {n} · {label}
      </span>
      {extra}
    </div>
    <h2 id={id} className="xp-h2">
      {children}
    </h2>
  </div>
);
const Pct = ({ bps }: { bps: number }) => `${bps / 100}%`;

export default async function Experience() {
  const { stats, pet, campaign, at } = await readLive();
  const p = pet.ok ? pet.data : null;
  const s = stats.ok ? stats.data : null;
  const camp = campaign.ok ? campaign.data : null;
  const line = camp?.line ?? null;
  const asleep = p?.compute != null && BigInt(p.compute.budget) === 0n;
  const bps = p?.compute?.shareBps;
  const paid = s ? BigInt(s.paidWei) : null;
  const [toDevs, toCompute] = paid != null && bps != null ? split(paid, bps) : [null, null];
  const petName = p?.name ?? "mochi";
  const seeded = Boolean(s?.seeded || p?.seeded);

  return (
    <div className="xp">
      {/* 1 · hook */}
      <section aria-labelledby="h-hook" className="xp-hook">
        <div className="xp-hook-inner">
          <div className="xp-eyebrow" style={{ color: "#FF5A3C" }}>
            THE 90-SECOND TOUR · NO WALLET, NO INSTALL
          </div>
          <h1 id="h-hook" className="xp-h1">
            Your agent makes you wait.
            <br />
            <span style={{ color: "#FF5A3C" }}>Gremlo makes the wait pay.</span>
          </h1>
          <p className="xp-lede">A pixel pet in your MacBook notch. It holds one sponsored line while your coding agent works, and the money it earns pays for its own AI.</p>
          <ul className="xp-chips">
            {CHIPS.map(([c, t]) => (
              <li key={t}>
                <i style={{ background: c }} />
                {t}
              </li>
            ))}
          </ul>
          <div className="xp-cta">
            <a href="#pet" className="xp-btn xp-btn-solid">
              Start the tour
            </a>
            <a href="#proof" className="xp-btn xp-btn-ghost">
              <LiveDot />
              Skip to live proof
            </a>
          </div>
        </div>
        <nav aria-label="Tour" className="xp-tour">
          <ol>
            {TOUR.map(([h, c, t]) => (
              <li key={h}>
                <a href={h} style={{ borderTopColor: c }}>
                  {t}
                </a>
              </li>
            ))}
          </ol>
        </nav>
      </section>

      {/* 2 · meet the pet */}
      <section id="pet" aria-labelledby="h-pet" className="xp-sec">
        <div className="xp-in">
          <div className="xp-head">
            <div className="xp-eyebrow" style={{ color: "#FF5A3C" }}>
              01 · MEET THE PET
            </div>
            <h2 id="h-pet" className="xp-h2">
              It lives in your notch and works when your agent works.
            </h2>
            <p className="xp-p">It peeks out when the agent starts, holds the sign while it runs, knocks before a risky command, and throws a party when the run is done. Tap a step, or let it play.</p>
          </div>
          <Demo line={line} campaignId={camp?.campaignId ?? null} />
        </div>
      </section>

      {/* 3 · money loop */}
      <section id="loop" aria-labelledby="h-loop" className="xp-sec xp-loop">
        <div className="xp-in">
          <Head n="02" label="THE MONEY LOOP" color="#FFC93C" id="h-loop">
            A brand pays for a real view. You earn. The pet eats.
          </Head>
          <ol className="xp-cards">
            {LOOP.map((l) => (
              <li key={l.num} className="xp-card xp-loopcard">
                <span className="xp-mono" style={{ color: l.color, fontSize: 13, fontWeight: 500 }}>
                  {l.num}
                </span>
                <span className="xp-h3">{l.title}</span>
                <span className="xp-small">{l.body}</span>
                <span className="xp-foot">{l.foot}</span>
              </li>
            ))}
          </ol>

          <div className="xp-card xp-split">
            <div className="xp-row">
              <span className="xp-livepill">
                <LiveDot />
                LIVE TOTALS
              </span>
              <span className="xp-h3 xp-h3-lg">Where every view’s money has gone so far</span>
            </div>
            {paid == null ? (
              <Down />
            ) : (
              <>
                {bps != null && toDevs != null && toCompute != null && (
                  <div role="img" aria-label={`${100 - bps / 100} percent to developers, ${bps / 100} percent to the pet's compute budget`} className="xp-bar">
                    <div style={{ flex: 10_000 - bps, background: "#8FD14F" }} />
                    <div style={{ flex: bps, background: "#B48CFF" }} />
                  </div>
                )}
                <div className="xp-amounts">
                  <div>
                    <div className="xp-label">Paid by brands</div>
                    <div className="xp-num">
                      {near4(paid)} <small>NEAR</small>
                    </div>
                  </div>
                  {bps != null && toDevs != null && toCompute != null && (
                    <>
                      <div>
                        <div className="xp-label" style={{ color: "#8FD14F" }}>
                          To developers · {100 - bps / 100}%
                        </div>
                        <div className="xp-num">
                          {near4(toDevs)} <small>NEAR</small>
                        </div>
                      </div>
                      <div>
                        <div className="xp-label" style={{ color: "#B48CFF" }}>
                          To the pet’s compute · <Pct bps={bps} />
                        </div>
                        <div className="xp-num">
                          {near4(toCompute)} <small>NEAR</small>
                        </div>
                      </div>
                    </>
                  )}
                </div>
                {bps == null && <Down>The split needs the pet’s compute share.</Down>}
              </>
            )}
            <div className="xp-note">Testnet NEAR. Tiny on purpose: this is one pet and a handful of real views, not a forecast.</div>
          </div>

          <div className="xp-versus">
            <div className="xp-card xp-dashed">
              <span className="xp-tag" style={{ color: "rgba(244,242,237,.62)" }}>
                MOST AGENT PROJECTS
              </span>
              <span className="xp-h3 xp-h3-lg" style={{ color: "rgba(244,242,237,.85)" }}>
                Guard what an agent is allowed to spend.
              </span>
              <span className="xp-small">Firewalls, limits and allowlists. Useful, and one-sided.</span>
            </div>
            <div className="xp-card xp-gremlo">
              <span className="xp-tag" style={{ color: "#FF5A3C" }}>
                GREMLO
              </span>
              <span className="xp-h3 xp-h3-lg">Turns agent wait-time into a two-sided market.</span>
              <span className="xp-small" style={{ color: "rgba(244,242,237,.82)" }}>
                Brands get a verified, human view. Developers get paid for time they were losing anyway. And the ad money feeds the pet’s brain.
              </span>
            </div>
          </div>
        </div>
      </section>

      {/* 4 · brain */}
      <section id="brain" aria-labelledby="h-brain" className="xp-sec">
        <div className="xp-in xp-brain">
          <div className="xp-brain-l">
            <div className="xp-eyebrow" style={{ color: "#B48CFF" }}>
              03 · THE BRAIN
            </div>
            <h2 id="h-brain" className="xp-h2">
              Every thought is a signed AI call, paid on chain.
            </h2>
            <ul className="xp-ticks">
              {[
                "When the pet decides what to do, it asks NEAR AI Cloud, running privately inside a TEE.",
                "Each call is charged to the pet’s compute budget on chain, with its completion ID in the record.",
                "No budget, no thinking. The pet goes to sleep instead of faking a thought.",
              ].map((t) => (
                <li key={t}>
                  <Tick />
                  {t}
                </li>
              ))}
            </ul>
            {!pet.ok && <Down />}
            {asleep && (
              <div className="xp-card xp-asleep">
                <Spr row={26} n={4} slow style={{ flex: "none" }} />
                <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                  <span className="xp-livepill xp-plain">
                    <LiveDot />
                    LIVE · {petName.toUpperCase()} RIGHT NOW
                  </span>
                  <span style={{ fontSize: 17 }}>
                    <b>Asleep.</b> {p?.moodReason ?? "compute budget empty"}. It will think again when the next view pays its budget.
                  </span>
                </div>
              </div>
            )}
          </div>

          <div className="xp-card xp-thought">
            <div className="xp-row">
              <span className="xp-tag" style={{ color: "#B48CFF" }}>
                ONE REAL THOUGHT
              </span>
              <span className="xp-mono xp-dim">15 Nov · final testnet run</span>
            </div>
            <dl className="xp-dl">
              <dt>Decision</dt>
              <dd className="xp-mono">work</dd>
              <dt>Model</dt>
              <dd className="xp-mono">deepseek-ai/DeepSeek-V4.1-Flash-1017</dd>
              <dt>Completion ID</dt>
              <dd className="xp-mono">chatcmpl-cc26d4e5-abf1-4837-b10f-7543f37ce156</dd>
              <dt>Charged</dt>
              <dd className="xp-mono">
                0.0005 NEAR ·{" "}
                <a href={txLink("E1vh3VKeVobQJPZjC5PKcpmiTfWzoqkGurW4KhCSMH1d")} target="_blank" rel="noreferrer">
                  E1vh3VKe…MH1d ↗
                </a>
              </dd>
            </dl>
            <div className="xp-verify">
              <div className="xp-mono" style={{ fontSize: 14, color: "rgba(244,242,237,.82)" }}>
                <span style={{ color: "#8FD14F" }}>$</span> npm run verify chatcmpl-cc26d4e5…
              </div>
              <div className="xp-row" style={{ flexWrap: "nowrap" }}>
                <span className="xp-signed">SIGNED</span>
                <span style={{ fontSize: 14, color: "rgba(244,242,237,.78)" }}>by 0xfe00…337e, an attested key of the NEAR TEE that served it</span>
              </div>
            </div>
            <div className="xp-note">Smart-model calls cost 0.0005 NEAR, cheap ones 0.0001: a fixed per-tier rate, not the real USD bill.</div>
          </div>
        </div>
      </section>

      {/* 5 · live proof */}
      <section id="proof" aria-labelledby="h-proof" className="xp-sec xp-proof">
        <div className="xp-in xp-proofin">
          <div className="xp-head">
            <div className="xp-eyebrow-row">
              <span className="xp-eyebrow" style={{ color: "#8FD14F" }}>
                04 · LIVE PROOF
              </span>
              <span className="xp-livepill xp-plain">
                <LiveDot />
                pulled from the Gremlo API when this page loads
              </span>
            </div>
            <h2 id="h-proof" className="xp-h2">
              It’s running on NEAR testnet right now.
            </h2>
            <p className="xp-p">Every number here is read live from the contract’s records. Every hash opens on nearblocks.</p>
            <div className="xp-small xp-dim">
              {stats.ok || pet.ok || campaign.ok ? (
                <>
                  Last read from the API {istWhen(Math.floor(at / 1000))} IST; refreshed at most every {REVALIDATE} s.
                </>
              ) : (
                <>The API could not be read.</>
              )}
              {seeded && (
                <>
                  {" "}
                  <b className="xp-seeded">Seeded data: not real money.</b>
                </>
              )}
            </div>
          </div>

          {s ? (
            <div className="xp-stats">
              {[
                ["Campaigns funded", String(s.campaigns), "on vault.gremlo.testnet"],
                ["Views settled", s.settledViews, "signed on a paired Mac"],
                ["Paid by brands", near4(s.paidWei), "NEAR (testnet)"],
                ["Charged for AI", near4(s.computeChargedWei), BigInt(s.paidWei) > 0n ? `NEAR · ${(BigInt(s.computeChargedWei) * 100n) / BigInt(s.paidWei)}% of paid` : "NEAR"],
              ].map(([l, v, u]) => (
                <div key={l} className="xp-card xp-stat">
                  <div className="xp-label">{l}</div>
                  <div className="xp-big">{v}</div>
                  <div className="xp-dim" style={{ fontSize: 13 }}>
                    {u}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <Down />
          )}

          <div className="xp-two">
            <div className="xp-card xp-mochi">
              {p ? (
                <>
                  <div className="xp-row" style={{ flexWrap: "nowrap", gap: 14 }}>
                    <Spr row={26} n={4} fw={96} slow style={{ flex: "none" }} />
                    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                      <span className="xp-name">{p.name}</span>
                      <span className="xp-small" style={{ fontSize: 14 }}>
                        a real pet · {p.species ?? "gremlo"} species · {p.stage ?? "hatchling"}
                      </span>
                    </div>
                  </div>
                  <dl className="xp-kv">
                    <dt>Mood</dt>
                    <dd style={{ color: p.mood === "hungry" || p.mood === "asleep" ? "#FFC93C" : "#8FD14F" }}>{p.mood}</dd>
                    <dt>Why</dt>
                    <dd style={{ textAlign: "right" }}>{p.moodReason ?? "no reason reported"}</dd>
                    <dt>Compute budget</dt>
                    <dd className="xp-mono">{p.compute ? near4(p.compute.budget) : "—"} NEAR</dd>
                    <dt>Earned for its owner</dt>
                    <dd className="xp-mono">{p.earnedWei == null ? "—" : near4(p.earnedWei)} NEAR</dd>
                    <dt>Paid views</dt>
                    <dd className="xp-mono">{p.paidViews ?? "—"}</dd>
                    <dt>Mac paired</dt>
                    <dd style={{ color: p.paired ? "#8FD14F" : undefined }}>{p.paired ? "yes · Secure Enclave key" : "not right now"}</dd>
                    <dt>Compute share</dt>
                    <dd className="xp-mono">{bps == null ? "—" : <Pct bps={bps} />}</dd>
                    <dt>Owner</dt>
                    <dd className="xp-mono" style={{ fontSize: 13 }}>
                      {p.owner}
                    </dd>
                  </dl>
                </>
              ) : (
                <Down />
              )}
              <Link href="/live" style={{ marginTop: "auto", fontSize: 15 }}>
                Open the live numbers page ↗
              </Link>
            </div>

            <div className="xp-card xp-thoughts">
              <div className="xp-h3 xp-h3-lg" style={{ fontSize: 26 }}>
                {petName[0].toUpperCase() + petName.slice(1)}’s last thoughts, each paid on chain
              </div>
              {p ? (
                <>
                  <div className="xp-scroll" tabIndex={0} role="region" aria-label="Last thoughts, scrolls sideways on narrow screens">
                    <table>
                      <thead>
                        <tr>
                          <th scope="col">WHEN (IST)</th>
                          <th scope="col">DECIDED</th>
                          <th scope="col">MODEL</th>
                          <th scope="col">NEAR AI REQUEST</th>
                          <th scope="col">CHARGE TX</th>
                        </tr>
                      </thead>
                      <tbody>
                        {p.lastThoughts.map((t) => (
                          <tr key={t.requestId + t.at}>
                            <td className="xp-mono" style={{ whiteSpace: "nowrap" }}>
                              {istWhen(t.at)}
                            </td>
                            <td>
                              <span className="xp-mono" style={{ fontSize: 13, color: ACTION_COLOR[t.action] ?? "rgba(244,242,237,.78)" }}>
                                {t.action}
                              </span>
                            </td>
                            <td>{t.model ? modelName(t.model) : "—"}</td>
                            <td className="xp-mono" title={t.requestId}>
                              {shortReq(t.requestId)}
                            </td>
                            <td className="xp-mono">
                              {t.chargeTx ? (
                                <a href={txLink(t.chargeTx)} target="_blank" rel="noreferrer">
                                  {shortHash(t.chargeTx)} ↗
                                </a>
                              ) : (
                                "—"
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <div className="xp-meals">
                    <span className="xp-dim">Meals (views settled to {petName}):</span>
                    {p.meals?.length ? (
                      p.meals.map((h) => (
                        <a key={h} className="xp-mono" href={txLink(h)} target="_blank" rel="noreferrer">
                          {shortHash(h)} ↗
                        </a>
                      ))
                    ) : (
                      <span>none yet</span>
                    )}
                  </div>
                </>
              ) : (
                <Down />
              )}
              <div className="xp-meals xp-dim" style={{ marginTop: "auto" }}>
                <span>
                  Contract:{" "}
                  <a className="xp-mono" href="https://testnet.nearblocks.io/address/vault.gremlo.testnet" target="_blank" rel="noreferrer">
                    vault.gremlo.testnet ↗
                  </a>
                </span>
                <span>
                  Every transaction, explained:{" "}
                  <a href={PROOF_MD} target="_blank" rel="noreferrer">
                    PROOF.md ↗
                  </a>
                </span>
              </div>
            </div>
          </div>

          <div className="xp-card xp-strip">
            <span className="xp-livepill xp-plain">
              <LiveDot />
              LIVE · THE LINE PETS HOLD RIGHT NOW
            </span>
            {camp && line ? (
              <>
                <span className="xp-sign xp-sign-inline">
                  <span className="xp-ad">AD</span>
                  {line}
                </span>
                <span className="xp-small" style={{ fontSize: 14 }}>
                  campaign {camp.campaignId} · {camp.brand} · {formatNear(BigInt(camp.ratePerImpression))} NEAR per view
                </span>
                <Link href={`/brand?c=${encodeURIComponent(camp.campaignId)}`} style={{ marginLeft: "auto", fontSize: 15 }}>
                  See the campaign ↗
                </Link>
              </>
            ) : campaign.ok ? (
              <span className="xp-small">No campaign is running right now.</span>
            ) : (
              <Down />
            )}
          </div>
        </div>
      </section>

      {/* 6 · built vs next */}
      <section id="status" aria-labelledby="h-status" className="xp-sec">
        <div className="xp-in">
          <Head n="05" label="BUILT VS NEXT" color="#4CC9FF" id="h-status">
            What works today, and what doesn’t yet.
          </Head>
          <div className="xp-twocol">
            <div className="xp-card xp-works">
              <span className="xp-tag" style={{ color: "#8FD14F", fontSize: 13 }}>
                WORKS TODAY
              </span>
              {WORKS.map((w) => (
                <div key={w} className="xp-item">
                  <Tick c="#8FD14F" w={2.4} />
                  <span>{w}</span>
                </div>
              ))}
            </div>
            <div className="xp-card xp-notyet">
              <span className="xp-tag" style={{ fontSize: 13, color: "rgba(244,242,237,.78)" }}>
                NOT YET, HONESTLY
              </span>
              {NOT_YET.map((n) => (
                <div key={n} className="xp-item" style={{ color: "rgba(244,242,237,.88)" }}>
                  <svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="rgba(244,242,237,.62)" strokeWidth="2.2" strokeLinecap="round">
                    <circle cx="12" cy="12" r="8" />
                    <path d="M12 8v4l2.5 2" />
                  </svg>
                  <span>{n}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* 7 · go deeper */}
      <section id="next" aria-labelledby="h-next" className="xp-sec xp-next">
        <div className="xp-in">
          <Head n="06" label="GO DEEPER" color="#F4F2ED" id="h-next">
            Your next 60 seconds.
          </Head>
          <div className="xp-videos">
            {[
              { href: "https://youtu.be/g5L31kJ2dRQ", img: "/experience/poster-demo.jpg", alt: "Video poster: Meet Gremlo, 1:30", t: "Watch the 1:30 demo", b: "The whole idea, fast. YouTube." },
              {
                href: "https://youtu.be/-QK3U_Z1n5s",
                img: "/experience/poster-walkthrough.jpg",
                alt: "Video poster: the full walkthrough, 4:40",
                t: "The full walkthrough · 4:40",
                b: "One view, start to finish, with the real transactions.",
              },
            ].map((v) => (
              <a key={v.href} className="xp-link xp-video" href={v.href} target="_blank" rel="noreferrer">
                <img src={v.img} alt={v.alt} width={1200} height={676} loading="lazy" decoding="async" />
                <span>
                  <span className="xp-h3" style={{ fontSize: 24 }}>
                    {v.t}
                  </span>
                  <span className="xp-small">{v.b}</span>
                </span>
              </a>
            ))}
          </div>
          <div className="xp-links">
            {LINKS.map((k) => {
              const inner = (
                <>
                  <span className="xp-tag" style={{ color: k.color, letterSpacing: "1.4px" }}>
                    {k.tag}
                  </span>
                  <span style={{ fontWeight: 600, fontSize: 18 }}>
                    {k.title} <span aria-hidden="true">↗</span>
                  </span>
                  <span className="xp-small" style={{ fontSize: 14 }}>
                    {k.body}
                  </span>
                </>
              );
              return k.ext ? (
                <a key={k.title} className="xp-link xp-lk" href={k.href} target="_blank" rel="noreferrer">
                  {inner}
                </a>
              ) : (
                <Link key={k.title} className="xp-link xp-lk" href={k.href}>
                  {inner}
                </Link>
              );
            })}
          </div>
          <div className="xp-oneline">
            <Spr row={4} n={5} fw={96} style={{ flex: "none" }} />
            <div style={{ flex: "1 1 320px", display: "flex", flexDirection: "column", gap: 8 }}>
              <span className="xp-tag" style={{ color: "#FF5A3C" }}>
                IF YOU REMEMBER ONE SENTENCE
              </span>
              <p>{ONE_LINE}</p>
            </div>
            <CopyLine text={ONE_LINE} />
          </div>
        </div>
      </section>
    </div>
  );
}
