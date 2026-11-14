// Haptics.swift · haptic choreography. Replaces round 3's HapticPlayer. Reference code, not compiled here.
//
// The Mac can't play stronger taps: 3 patterns, Force Touch trackpad only, finger on the pad.
// What makes them feel strong is TIMING (ideas 19–21):
//  • fire on the frame motion peaks (Spring.onPeak) with performanceTime .drawCompleted, so the tap lands with the pixels
//  • pair every tap with a sound and a visible change, never a lone tap
//  • texture: rapid alignment ticks (≥ 35 ms apart) while scrubbing or dragging across edges
//  • heartbeat: slow double tap while something waits on you, only while the finger is on the pad

import AppKit

enum Haptic { case tick, snap, boop, purr, knock, thud, stomp, allow, deny, hatch, heartbeat, stage2 }

final class Haptics {
    static let shared = Haptics()
    enum Level { case on, subtle, off }
    var level: Level = .on

    private let performer = NSHapticFeedbackManager.defaultPerformer
    private var last = Date.distantPast, lastTick = Date.distantPast, lastPurr = Date.distantPast
    private var heartbeat: Timer?

    private let recipes: [Haptic: [(NSHapticFeedbackManager.FeedbackPattern, TimeInterval)]] = [
        .tick: [(.alignment, 0)], .snap: [(.levelChange, 0)], .boop: [(.generic, 0)],
        .purr: [(.alignment, 0), (.alignment, 0.09), (.alignment, 0.18), (.alignment, 0.27)],
        .knock: [(.generic, 0), (.generic, 0.12)], .thud: [(.levelChange, 0), (.generic, 0.04)],
        .stomp: [(.levelChange, 0), (.levelChange, 0.07), (.levelChange, 0.14)],
        .allow: [(.levelChange, 0)], .deny: [(.generic, 0), (.generic, 0.08)],
        .hatch: [(.alignment, 0), (.alignment, 0.15), (.alignment, 0.30), (.levelChange, 0.60)],
        .heartbeat: [(.generic, 0), (.generic, 0.14)],
        .stage2: [],                                    // the trackpad already clicks at stage 2: add nothing
    ]

    func play(_ h: Haptic, at time: NSHapticFeedbackManager.PerformanceTime = .now) {
        guard level != .off, !ScreenShare.isActive, !SponsoredLine.isVisible else { return }   // never during a share, never for an ad
        if level == .subtle && h != .tick { return }
        let now = Date()
        if h == .tick {                                  // texture ticks may be dense, but not denser than 35 ms
            guard now.timeIntervalSince(lastTick) >= 0.035 else { return }; lastTick = now
        } else {
            guard now.timeIntervalSince(last) >= 0.1 else { return }; last = now
        }
        if h == .purr { guard now.timeIntervalSince(lastPurr) >= 10 else { return }; lastPurr = now }
        for (pattern, delay) in recipes[h] ?? [] {
            if delay == 0 { performer.perform(pattern, performanceTime: time) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.performer.perform(pattern, performanceTime: .now) } }
        }
    }

    /// #21: while an approval waits. Stops on answer, on dismiss, or after 30 s.
    func startHeartbeat() {
        stopHeartbeat()
        var beats = 0
        heartbeat = .scheduledTimer(withTimeInterval: 1.4, repeats: true) { [weak self] t in
            beats += 1; if beats > 21 { t.invalidate(); return }
            if TrackpadTouch.fingerDown { self?.play(.heartbeat) }   // NSTouch tracking on the notch view's window; skip if no finger
        }
    }
    func stopHeartbeat() { heartbeat?.invalidate(); heartbeat = nil }
}

/// Is a finger resting on the trackpad? Track NSTouch phases on the notch window (allowedTouchTypes = [.indirect]).
enum TrackpadTouch { static var fingerDown = false }
