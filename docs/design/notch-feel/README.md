# Gremlo · notch feel export

| Path | What |
|---|---|
| `NOTCH_FEEL.md` | All 30 ideas with the exact numbers: springs, squash, stagger, lean, gestures, haptic timing, rim, particles, sound, Mac events, perf budget, permissions |
| `BUILD_BRIEF_notch_feel.md` | Build order for Claude Code: phase A (demo), B (gestures), C (personality), and the definition of done |
| `swift/` | Reference Swift (macOS 14 SDK): Spring, NotchDriver (display link + 8 fps sprite clock), NotchShape (path, ears, rim, depth), NotchController (states, gestures), Haptics (peak-frame taps, texture, heartbeat), Particles, SoundKit, MacEvents, Extras (drop zone, fling, idle life, typing pace, music). **Not compiled here: a spec in code** |
| `lab/index.html` | The Notch Lab. Serve the folder (`npx serve lab`) and play with it. The numbers match the spec |
| `sounds/` | `tick.wav` and `shutter.wav` (new, 44.1 kHz mono, same format as the round-2 kit) |
| `haptics/approval-watch.ahap` | The iPhone approval pattern; the Watch mapping is noted inside |
| `screens/` | Lab screenshots of the main states |
