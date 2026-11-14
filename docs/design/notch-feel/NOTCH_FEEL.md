# Gremlo · notch feel (all 30 ideas)

The playable reference is the **Notch Lab** artifact (`lab/index.html` in this export, serve the folder). Every number below is the one the lab uses. Swift reference code is in `swift/`. It is written against the macOS 14 SDK but **was not compiled here**, so treat it as a precise spec in Swift, not drop-in code.

**Types the Swift assumes from the app:** `ScreenShare`, `SponsoredLine`, `Focus`, `ScreenState`, `Settings`, `NSWorkspaceProxy` (reduce motion), `ContentStack` (renders the rows for a mode), `Agents`, `Approvals`, `PetRow`, `PetSpriteLayer`, `Palette`, `Sprites`, `VolumeRow`, `MusicRow`, `NotchCenter`. Wire them to the real ones.

Rules that don't change:
- Haptics never fire for a sponsored line and are never the only signal.
- Everything goes quiet during a screen share.
- Reduce Motion is respected everywhere.
- Notch Live never shows ads.

---

## 1. Motion

| # | Idea | Spec |
|---|---|---|
| 1 | **Springs everywhere** | `Spring` (response, damping), retargetable, velocity carries over. **open** `.42 / .70` (≈6% overshoot), **close** `.30 / .88`, **press** `.14 / .60`, **release** `.22 / .45`, **lean** `.25 / .80`, **pull** `.35 / .70`. Height uses the width's response + 0.03 s, so it lands a beat later and the shape feels heavy. |
| 2 | **Squash & stretch** | One `squash` spring (`.22 / .45`). Kick it −2.2 on opening (wide and short, sides bow out via `bulge`) and +1.4 on closing (tall and thin). Scale is `1 ∓ 0.03·squash` around the top centre. The path is rebuilt per frame, never a view resize. |
| 3 | **Staggered content** | The shape moves first. Content rows fade in starting 60 ms later, 45 ms apart: opacity 180 ms ease plus a 6 pt slide-up on the release spring. Closing reverses instantly (content out in 80 ms, then the shape). |
| 4 | **Lean toward the cursor** | A global `mouseMoved` monitor (mouse events need no permission). Weighted distance `d = hypot(0.6·dx, dy)` from the notch top centre. Within 140 pt the notch grows by up to +18 w / +4 h and shifts up to 8 pt toward the cursor. Under 34 pt it enters **hover** (tick); past 70 pt it leaves. |
| 5 | **Press dent** | Mouse down → 0.955 scale on the press spring plus a **boop**. Mouse up → back to 1 on the release spring (overshoots to ~1.01). Force-click pressure deepens the dent by up to 4%. |
| 6 | **Pet lives inside** | In peek rows the sprite faces the cursor and only redraws when the side changes. In idle moments the pet bumps the notch edge (edgepeek row). |
| 16 | **Idle life** | Every 20–40 s at rest, one of yawn / peek / edgepeek / gaze for 2.2 s. Never during a share, a meeting or Focus. Night (22:00–06:00) uses the night row. |
| 17 | **Depth** | When expanded, a shadow on the desktop (`shadowOpacity = 0.45 × open`, radius 24, y +10) plus a blur halo behind (vibrancy view 60 pt wider than the notch). |
| 18 | **Rolling numbers** | Digit columns in a clipped 14 pt cell, moved on the release spring. Mono, tabular figures. |

## 2. Interaction

| # | Idea | Spec |
|---|---|---|
| 7 | **Rubber-band pull, flick** | Pulling down adds height `band = dy·0.55/(1+dy/320)·2`. A **tick** each way across 130 pt. Release past it opens the **room** (snap); short of it springs back. Flicking up faster than 500 pt/s on a big state dismisses it (whoosh). |
| 8 | **Scroll to switch agents** | Two-finger scroll over the open notch. Every 40 pt of accumulated delta = one detent: next agent, **tick** and tick sound, content slides 30 pt in the scroll direction. The accumulator resets when the gesture ends. |
| 9 | **Force click** | `pressureChange`: stage 2 → **quick actions** (Approve safe calls · Mute 1h · Open room). Add no haptic at stage 2: the trackpad clicks itself. Without Force Touch, hold 480 ms instead (the lab does this). |
| 10 | **Fling the pet out** | Drag the pet in open/room → it moves into its own transparent panel. Release velocity from the last ~6 samples, gravity 2200 pt/s², bounces lose 65%. A **thud** when it lands at more than 240 pt/s. It sits 1.8 s, walks home at 140 pt/s, climbs in, then "Mochi is home". |
| 11 | **Keyboard** | ⌥⌘N toggle (configurable), ←/→ pick in approvals or switch agents, ⏎ allow the picked option, Esc close. Every key gets a tick. |
| 12 | **Drop zone mouth** | Drag enter → **drop** (320×92, pet's gulp row frame 0 = open mouth, "drop to copy the path") plus snap. Drop → gulp, chomp, "Ready to paste". The clipboard gets the paths (quoted if they contain spaces) and the image for a single image. Nothing is uploaded. |
| 26 | **Easter eggs** | Triple-click → random trick (backflip with the jump arc, juggle, moonwalk with the slide), 2.4 s. The Konami code → a disco rim (hue cycle 3.6 s), moonwalk and confetti. |

## 3. Haptics (the honest version)

A Mac can't play a stronger tap. There are three patterns (`.alignment`, `.levelChange`, `.generic`), only on a Force Touch trackpad, only with a finger on it. What makes a tap feel stronger is **timing and pairing**:

| # | Idea | Spec |
|---|---|---|
| 19 | **Tap on the overshoot frame** | Opening springs pass `onPeak`. It fires on the step where velocity flips sign past the target, and plays **snap** with `performanceTime: .drawCompleted`, so the tap lands with the pixels. The lab's scope draws a tick exactly there. |
| 20 | **Texture taps** | **tick** (`.alignment`) per event bar while scrubbing the session, per detent while scrolling, and when crossing the pull threshold. Ticks may be dense, but never closer than 35 ms apart. Every other haptic keeps the 100 ms gap. |
| 21 | **Heartbeat** | While an approval waits: **heartbeat** (generic, generic +140 ms) every 1.4 s, only while a finger is on the trackpad (NSTouch tracking), and for at most 30 s. |
| 23 | **Watch for the strong buzz** | Approvals → Watch `.notification` then `.click` 0.4 s later. iPhone uses `haptics/approval-watch.ahap`. Done → `.success`. |

Full map (adds to round 3's `HAPTICS.md`):

| Moment | Haptic |
|---|---|
| hover enter | tick |
| press | boop |
| any opening spring, on the peak frame | snap |
| pull past 130 / back under | tick / tick |
| room opens | snap |
| scrub bar · scroll detent · key | tick |
| force click stage 2 | none (the hardware clicks) |
| drop zone accepts / leaves | snap / tick |
| gulp | boop |
| pet grabbed / lands | snap / thud |
| approval appears · still waiting | knock · heartbeat |
| allow / deny | allow / deny |
| battery low | knock |
| plugged in | boop |

## 4. Look

| # | Idea | Spec |
|---|---|---|
| 13 | **Live rim** | A 3 pt stroke of the notch path (half hidden under the body, so ~1.5 pt shows) holding a conic gradient. **Flow** (thinking) spins the gradient in 2.2 s. The mask never spins. **Solid** for approval, open, done, fail, battery, charging. Colours: Claude `#D97757`, Codex `#10A37F`, Cursor `#4C8DFF`, Gremlo `#FF5A3C`, done `#8FD14F`, merge `#B48CFF`, fail `#FF5A3C`, battery `#FFB020`. Colour only, never a logo. Plus a soft glow: shadow 28 pt in the agent colour, y +6. |
| 14 | **Particles** | `CAEmitterLayer` bursts from the bottom edge, 120 ms of birth, then removed after 2.6 s. Confetti 60 (pet palette, gravity 520), sparks 36 (merge), smoke 14 (fail, rises), sweat 6 (battery). Budget 140 (50 in Low Power). Off with Reduce Motion. |
| 15 | **Progress scene** | A track inside the open notch; the walk-row pet stands at the progress edge. With an unknown ETA the pet walks in place and the fill pulses; never a made-up percentage. |
| 22 | **Sound kit** | AVAudioEngine with preloaded buffers and a 6-voice pool, under 10 ms latency. Off · **Subtle (default)** · Full. Muted during shares. The engine pauses after 20 s of silence. Mapping in `SoundKit.swift`: pop=door-open, close=door-close, tick=**tick.wav (new)**, chomp=meal, whoosh, shutter=**shutter.wav (new)**, chime=celebrate, thud, boing, fail. |

## 5. Mac events and personality

| # | Idea | Spec |
|---|---|---|
| 24 | **Reacts to the Mac** | **Volume:** a CoreAudio listener shows a volume row with the pet riding the fill for 1.8 s. **Battery ≤10%** (once per discharge): sweat, amber rim, knock. **Plug in:** the pet eats a ⚡︎ (gulp), boop. **Screenshot:** Spotlight `kMDItemIsScreenCapture` query, then shutter sound and a pose. Brightness is **not** done (no public API). We don't touch the system volume overlay. |
| 25 | **Typing pace** (opt-in) | Needs Accessibility trust. Keeps only the timestamps from the last 1.5 s, never key codes. Over 6 keys/s → a cheer for 1.8 s. 5 min with no typing → naps. |
| 27 | **Bops to music** (opt-in) | AppleScript to Music and Spotify every 5 s while enabled (Automation consent, `NSAppleEventsUsageDescription`), then a steady 2 Hz bop and the track name. MediaRemote (private) is not used, so it stays App Store-safe. |

## 6. Performance (28–30)

| | Budget | How |
|---|---|---|
| 28 | 120 Hz while moving | `NSView.displayLink` (macOS 14), `preferredFrameRateRange` 60–120. One `CATransaction` per frame with actions disabled. Only path, transform and opacity change. |
| 29 | **Idle = 0 frames** | The link pauses when every spring rests and no ticker runs. Sprites have their own 8 fps timer (tolerance 20 ms), which also pauses when the notch is hidden, the screen is asleep or locked, or a full-screen app owns the display. Targets: <0.5% CPU idle, <3% while thinking, <60 MB memory, the first hover frame within 16 ms. Measure with the Instruments Time Profiler and Animation Hitches. |
| 30 | **Low Power, Reduce Motion** | Low Power: 60 Hz cap, half the particles. Reduce Motion: springs become critically damped and ≤0.2 s, no squash, no particles, no flow spin, sprites hold frame 0, and the stagger is 0. |

## 7. Permissions

| Feature | Permission | Default |
|---|---|---|
| Lean, hover, scroll, gestures | none | on |
| Volume, battery, screenshots | none | on |
| Typing pace | Accessibility | **off**, ask in Settings |
| Music bop | Automation (Music, Spotify) | **off**, ask in Settings |
| Sound | none | Subtle |
