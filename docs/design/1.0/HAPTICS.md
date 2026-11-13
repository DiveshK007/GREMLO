# Gremlo haptics

Canvas board: **Haptics** on the "1.0 · round 3" page.

## The constraint that shapes everything
- **Mac:**
  - Only Force Touch trackpads give feedback, and only while a finger is on the pad. Mice get nothing.
  - Apps get three patterns from `NSHapticFeedbackManager`: `.alignment` (tick), `.levelChange` (firm), `.generic`. There are no custom waveforms.
  - So haptics only confirm things the user is touching. They are never an alert.
- **iPhone:** Core Haptics, with custom AHAP patterns in `haptics/*.ahap`.
- **Watch:** `WKInterfaceDevice.current().play(_:)` with the built-in types.
- **Web:** `navigator.vibrate` works on Android only, and only after the user has tapped the page once. iPhone Safari has no vibration API.

## Vocabulary
| Name | Mac recipe (pattern @ ms) | iPhone | Watch |
|---|---|---|---|
| tick | alignment @0 | UISelectionFeedbackGenerator | .click |
| snap | levelChange @0 | UIImpactFeedbackGenerator(.light) | .click |
| boop | generic @0 | boop.ahap | .click |
| purr | alignment @0, 90, 180, 270 | purr.ahap (continuous, fading) | none |
| knock | generic @0, 120 | knock.ahap | .notification |
| thud | levelChange @0, generic @40 | thud.ahap | .directionDown |
| stomp | levelChange @0, 70, 140 | stomp.ahap | .retry |
| allow | levelChange @0 | notification .success | .success |
| deny | generic @0, 80 | notification .warning | .failure |
| hatch | alignment @0, 150, 300, levelChange @600 | hatch.ahap | .success |
| celebrate | none (finger probably not on the pad) | celebrate.ahap | .success |

## Mac map
| Moment | Haptic |
|---|---|
| Cursor moving over the pet's alpha | purr (at most once every 10 s) |
| Click the pet | boop |
| 5th click in 6 s | stomp |
| Hold 150 ms (grab) | snap |
| Drag over a perchable title bar | tick |
| Drag into the notch (door accepts) | snap |
| Landing while the finger is still down | thud |
| Notch opens on hover | tick at `.drawCompleted`, so it lands with the shape |
| Click to pin | snap |
| Drag down to the room | tick at ⅓ and ⅔, snap on open |
| Two-finger swipe to the next agent | tick |
| Allow / deny clicked | allow / deny |
| Accessory snaps on in the Closet | tick |

**Force press (squish)**
- Set `petView.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)`.
- In `pressureChange(with:)`, map `event.pressure` within stage 1 onto the land row's squash frames.
- On entering stage 2, play celebrate frames. The trackpad already gives a physical click at each stage, so add no extra tap.

## Rules
- Settings: Haptics On (default) · Subtle (tick only) · Off. Also follows the system trackpad setting.
- Keep at least 100 ms between patterns.
- Nothing during a screen share. Nothing for a sponsored line, ever. Never the only signal for anything.
- Reduce Motion does not turn off haptics. It is a separate setting.

## Mac player (reference)
```swift
import AppKit

enum Haptic { case tick, snap, boop, purr, knock, thud, stomp, allow, deny, hatch }

final class HapticPlayer {
    enum Level { case on, subtle, off }
    static let shared = HapticPlayer()
    var level: Level = .on
    private var last = Date.distantPast, lastPurr = Date.distantPast
    private let performer = NSHapticFeedbackManager.defaultPerformer
    private let recipes: [Haptic: [(NSHapticFeedbackManager.FeedbackPattern, TimeInterval)]] = [
        .tick: [(.alignment, 0)], .snap: [(.levelChange, 0)], .boop: [(.generic, 0)],
        .purr: [(.alignment, 0), (.alignment, 0.09), (.alignment, 0.18), (.alignment, 0.27)],
        .knock: [(.generic, 0), (.generic, 0.12)], .thud: [(.levelChange, 0), (.generic, 0.04)],
        .stomp: [(.levelChange, 0), (.levelChange, 0.07), (.levelChange, 0.14)],
        .allow: [(.levelChange, 0)], .deny: [(.generic, 0), (.generic, 0.08)],
        .hatch: [(.alignment, 0), (.alignment, 0.15), (.alignment, 0.30), (.levelChange, 0.60)],
    ]

    func play(_ h: Haptic, at time: NSHapticFeedbackManager.PerformanceTime = .now) {
        guard level != .off, !ScreenShare.isActive else { return }   // ScreenShare: the app's existing share detector
        if level == .subtle && h != .tick { return }
        let now = Date()
        guard now.timeIntervalSince(last) >= 0.1 else { return }
        if h == .purr { guard now.timeIntervalSince(lastPurr) >= 10 else { return }; lastPurr = now }
        last = now
        for (pattern, delay) in recipes[h] ?? [] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.performer.perform(pattern, performanceTime: time) }
        }
    }
}
```

## Tests
- A table test that every Mac map row resolves to a recipe.
- A rate-limit test using an injected clock.
- A test that no haptic fires while `ScreenShare.isActive` is true or while a sponsored line is up.
