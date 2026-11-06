# Hackathon Playbook

What separated finalists and prize winners from everyone else at ETHGlobal Tokyo and New Delhi 2025, and what that means for Mumbai.

## The checklist

Score every idea against this before building. If one is missing, fix it or have a reason.

1. **Physical world meets onchain.** Something judges can hold or see: cards in a vault (Kura), a signing camera (LensMint), robots (Paybot), receipts (Halo), flights (JetLagged).
2. **One-line hook that describes an outcome.** "80% of the shards and you take the card home." "The mempool is the airwaves." If the tagline lists sponsors ("combining ENSv2, 1inch SwapVM, Uniswap v4 & World ID"), rewrite it.
3. **A real problem with real numbers.** Prove it, don't assert it. watermark opened with ENS DAO's real sale (~$323k at risk). Ours: the FabHotels ₹891 + ₹2,680 story. Losers said things like "security trilemma".
4. **Depth beats breadth.** Winners took 1–2 sponsor prizes (x402 Guard, Airlock, OniBlock, watermark: 1 each; Kura, Lortnoc Tahc: 2). Teams that integrated 3–4 sponsors mostly lost. Pick 2, add a third only if it does a job nothing else can.
5. **The sponsor's newest, deepest feature, not the basic API.** Custom SwapVM instructions, Uniswap auctions plus hook validation, ENSv2 per-record permissions.
6. **Every sponsor answers "why you?"** Kura: Uniswap finds the price, World blocks bots, ENS names each card. If removing a sponsor breaks nothing, judges notice.
7. **Bounded, accountable AI, not a chatbot.** The chain caps what the AI can do (watermark: it can tune but not move money), or it gets demoted when wrong (OniBlock).
8. **Crypto stays invisible.** calendefi (a calendar), NoNet (no internet), Angpao (a link), Paybot (no gas). Normal people can use it.
9. **Slot into tools people already use.** MetaMask plugin, browser extension, OpenAI-compatible endpoint. Standalone "protocols", "matrices" and "layers" lose.
10. **Narrow, sharp angle in a crowded category.** Everyone built "spending limits for agents". Winners asked "who is the agent actually paying?" and "what data is leaking?"

Originality is its own path: Patio Station made the finals on pure weirdness with no partner prize. "Use Ethereum in a way nobody expected" counts.

## Execution signals judges trust

- **Rigor you can point at.** "146 Foundry tests", fork tests against real deployed contracts, "fails closed", "never reverts on swaps".
- **Real data, not mocks.** Real mainnet addresses, forked real contracts, the real Uniswap PoolManager. Mocks are fine for setup; the demo moment must be real.
- **Verifiability.** "Every action can be recomputed from public data", plus receipts and events.
- **A live, clickable demo.** Deployed site, one-click "try it", embedded wallets with sponsored gas (Kura used Privy).
- **A magic demo moment.** Kura's webcam card scan. Patio's audio playing from pending transactions.
- **Finish every integration you claim.** A half-wired path (DSAP's v3 fallback) costs more credibility than leaving it out.
- **Report what you discovered.** x402 Guard found Cloudflare blocking default user agents and a docs bug in Intercepta's API; Airlock found an ENS resolver gotcha. It proves you built it and sponsors reward it.
- **A long, specific "How it's made".** Numbers, test counts, edge cases, and a "hacky bits" section on what was hard. AegisNet's few generic paragraphs lost.
- **Do the paperwork.** Arkiv, Whitechain and Uniswap all require feedback files. Many teams skip them; doing them properly is an edge.

## Sponsors

- **ENS is the universal glue.** It shows up in most Tokyo winners as the identity and permission layer and pairs with anything. A near-free extra pick, but only if you use v2 properly (per-record permissions), not just name resolution.
- **Mumbai's new sponsors have little or no prior art:** 0G, Arkiv, Whitechain, Arc, Definitive. Less copying, better odds.
- **Hedera has rewarded Indian finalists before** (MemeWarp). A credible pick here.

## Saturated: avoid or twist hard

- AI-agent spending limits + ENS + World approval: 15+ near-identical projects at Tokyo, only a couple won.
- Anti-scalping and fair drops: ScalpLess, Tenjō, RealClanker, Human Wall.
- Agent marketplaces and agent-pays-agent: Hubble, Tollgate, Agent's List.
- Copies of Tokyo winners. Other Indian teams are studying the same showcase.

## India signals (New Delhi 2025)

- Finalists leaned infrastructure-heavy and bold: offline transactions (NoNet), a private perp DEX (Nox), cross-chain memecoin arbitrage (MemeWarp).
- Local flavour helps, but the problem must be universal. Tokyo winners had Japanese names (Kura, Omamori, Takarabako) and global problems.

## Our ideas

| Idea | Prior art | Status |
|---|---|---|
| Pakka | None found | Open ground. Physical world, a real incident with numbers, invisible crypto, every sponsor with a job (Whitechain pays, ENS permissions, Arkiv disputes). |
| Pyaaz | ≈ Halo | Needs a twist |
| Bijli | ≈ Paybot | Needs a twist |
| Dabba | ≈ Hubble | Needs a twist |
| Shagun | ≈ Angpao | Needs a twist |

Open question for Pakka: the receipt or booking is the physical anchor, but how do people use it? Pick the existing surface (extension, link, WhatsApp) early so checklist items 1 and 9 both hold.

## The 4-minute pitch

1. **Pain with numbers.** A real incident, a real amount.
2. **One-line hook.** The outcome, not the stack.
3. **Live magic moment.** Real data, on screen.
4. **Proof.** Test counts, fork tests, onchain receipts.
5. **Why each sponsor.** One job per sponsor that only it can do.
