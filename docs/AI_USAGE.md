# How we used AI

ETHGlobal asks every team to say where and how AI tools were used. We used them openly. This is the log.

## Tools

- **Claude Code** (several sessions, one per area) for writing and testing code.
- **Claude (chat)** for planning, prior-art research, setup steps, debugging help, the web app first draft, and this documentation's first draft.
- **0G Private Computer** models inside the product itself (`0gm-1.0-35b-a3b`, `glm-5.3`). That is the product, not dev help.

## Spec files used

`CLAUDE.md` (project rules for Claude Code) and `BUILD_GUIDE.md` (architecture, checklists, timeline) are in the repo root. Claude Code worked from these.

## What AI did vs what we decided

| Area | AI-assisted | Human decisions and changes |
|---|---|---|
| Idea and scope | Brainstorming, prior-art research, sponsor fit analysis | Picked the concept and name, cut the scope to two sides, chose 0G + World, dropped other sponsors |
| Mac app (`apps/mac`) | Code drafts: overlay window, notch door, state machine, hook server, popover | Notch/door behaviour, the climb-home path, timings, testing on our Macs |
| Contract (`contracts`) | First draft of `CampaignVault.sol` and its tests; review that added the settle grace window and the closed-campaign fix | Contract rules (owner-only payout, refunds, operator limits), deploy and verify on Galileo |
| Server (`apps/server`) | Routes, World verify, settlement, mood from balance, tests | API shapes, honesty rules (no fake lines, no fake request IDs), merge decisions |
| Brain (`packages/brain`) | 0G client, mood-to-model mapping, safe-stop, tests | Model choice, spend cap on the API key |
| Web (`apps/web`) | First draft of the pages | World staging/production switch, explicit gas fix after testing, copy |
| Docs | First drafts of README, World debrief, this file | Edited and checked against what we actually built |

## Log

<!-- time - who - tool - what it produced - what you changed -->
- 2026-11-07 - Claude Code (Opus 5.5) - Mac impression reporting (5s sign, 1/min), server-side 1/min check + settle totals, /brand Settle button, landing pet illustration and CSS polish - human review pending
- 2026-11-07 - Claude Code - Mac pet: sprite folders (assets/pets, demo-pets override), eat animation + real wallet-gain bubble, visible mood; review fixes for stale poll replies and bad pet.json - human review pending
- 2026-11-07 - Claude Code (Opus 5.5) - Web v2 per BRIEF_WEB: tokens, landing with live sign, /brand and /pet restyle, Notchi hooks tone picker threaded to the 0G prompt - human review pending
- 2026-11-07 - Claude Code - Mac v2 (BRIEF_MAC 1-7): Codex sheet loader + notchi-ink default, hidden door, sign/working walks, upside-down top edge, emotions + 0G say bubble, popover v2 with settings, cursor hover/annoyance; review fixes - human review pending, not yet run on screen
- 2026-11-09 - Claude Code (Opus 5.5) - v2 branch: hook engine, device signatures, Arkiv mirror, deploy config, homepage v2, Mac demo controls, retention (earnings, streak, level, local wait time) and brand budget alerts + top-up - human review pending, not yet run on screen
