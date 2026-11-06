# How we used AI

ETHGlobal asks every team to say where and how AI tools were used. We used them openly; this is the log.

## Tools
- Claude Code (with Ponytail, gstack review/QA/debug, superpowers worktrees)
- Claude Design for UI mockups
- 0G Private Computer models inside the product itself (that is the product, not dev help)

## What AI did vs what we did
| Area | AI-assisted | Human decisions / changes |
|---|---|---|
| Idea and scope | Brainstorming, prior-art research | Picked the concept, cut scope, chose sponsors |
| UI | Mockups in Claude Design | Final layout, pet characters, animation timing |
| Mac app | Code drafts | Notch/door behaviour, hook mapping, testing on our Macs |
| 0G loop | Code drafts | Funding path, spend cap, safe-stop design |
| Contract, World, ENS | Code drafts | Contract rules, refund logic, proof checks, denied paths, record permissions |

## Log
<!-- add a line as you go: time - who - tool - what it produced - what you changed -->
- 19:01 - Mac - Claude Code - SwiftPM overlay app: transparent panel, spritesheet animation, hook server on 47474, state machine for 9 hook events - pending human review on device
- 19:18 - Mac - Claude Code - notch door (drawn in code, 4 states), drop-out with gravity, climb home via right wall and top edge, idle timeout - pending human review on device
