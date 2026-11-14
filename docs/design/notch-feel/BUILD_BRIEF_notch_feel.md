# Build brief: notch feel

Spec: `NOTCH_FEEL.md`. Feel reference: the Notch Lab (`lab/index.html`). Code shape: `swift/*.swift` (reference, not compiled here: fix API details as you go and keep the numbers).

**The submission closes today (14 Nov, UTC).** Build in this order and cut a demo video after phase A. Each phase ships on its own.

## Phase A · the demo (~1 day of work, all S)
1. `Spring.swift` and `NotchDriver.swift`: replace every timed notch animation with springs on the display link. Idle pauses the link.
2. `NotchShape.swift`: the notch as one path with ears; squash/stretch; rim with flow/solid; glow.
3. Content stagger (60 ms + 45 ms per row).
4. Haptic on the overshoot frame (`onPeak` → `.snap` at `.drawCompleted`); press dent; hover lean.
5. Sound kit, Subtle by default (add `tick.wav` and `shutter.wav` from `sounds/`).
6. Idle life (20–40 s) and the rolling numbers.

## Phase B · gestures (M)
7. Rubber-band pull → room; flick to dismiss; scroll detents between agents; keyboard.
8. Force click → quick actions; the drop-zone mouth.
9. Particles (confetti / sparks / smoke / sweat) with the budget.
10. Progress scene in the open notch; texture taps on the scrubber; approval heartbeat.

## Phase C · personality (M)
11. Fling the pet out (`FreePet`) and the walk home.
12. Mac events: volume, battery, plug in, screenshot.
13. Easter eggs; opt-in typing pace and music bop behind Settings toggles.
14. Watch approval pattern.

## Definition of done
- Instruments shows **0 display-link frames** at rest for 60 s, and no hitches over 2 frames while opening.
- The haptic fires on the peak frame (log the frame index in debug builds).
- Reduce Motion and Low Power behave per §6.
- No haptic or sound during a screen share or for a sponsored line.
- Every haptic has a visible pairing.
