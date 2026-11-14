// Spring.swift · Gremlo notch feel
// Reference code: written against the macOS 14 SDK, not compiled here. Treat as a spec in Swift.
//
// A damped spring you can retarget mid-flight. Velocity carries over, so grabbing the notch while it
// opens feels continuous. `onPeak` fires on the exact step the overshoot is biggest (velocity flips sign
// while past the target). That is the frame the haptic should land on (NOTCH_FEEL.md §3).

import Foundation
import QuartzCore

struct SpringParams {
    var response: Double      // seconds for one oscillation (SwiftUI's "response")
    var damping: Double       // 0 = wobbles forever, 1 = critically damped (no overshoot)

    static let open    = SpringParams(response: 0.42, damping: 0.70)   // ~6% overshoot, haptic on the peak
    static let close   = SpringParams(response: 0.30, damping: 0.88)   // snappy, tiny settle
    static let press   = SpringParams(response: 0.14, damping: 0.60)   // the 96% dent
    static let release = SpringParams(response: 0.22, damping: 0.45)   // springs back past 100% once
    static let lean    = SpringParams(response: 0.25, damping: 0.80)   // follows the cursor
    static let squash  = SpringParams(response: 0.22, damping: 0.45)   // jelly wobble after a size change
    static let pull    = SpringParams(response: 0.35, damping: 0.70)   // rubber band returning

    /// Reduce Motion: no overshoot, quick.
    var reduced: SpringParams { SpringParams(response: min(response, 0.2), damping: 1) }
}

final class Spring {
    private(set) var value: Double
    private(set) var velocity: Double = 0
    private(set) var target: Double
    private var k: Double = 0, c: Double = 0
    private var onPeak: (() -> Void)?
    private var direction: Double = 0

    init(_ value: Double, _ p: SpringParams = .open) {
        self.value = value; self.target = value; set(p)
    }

    func set(_ p: SpringParams) {
        let p = Motion.reduce ? p.reduced : p
        k = pow(2 * .pi / p.response, 2)          // stiffness for mass 1
        c = 4 * .pi * p.damping / p.response      // damping coefficient
    }

    func animate(to t: Double, _ p: SpringParams? = nil, onPeak: (() -> Void)? = nil) {
        if let p { set(p) }
        target = t; self.onPeak = onPeak; direction = (t - value).sign == .minus ? -1 : 1
        NotchDriver.shared.wake()
    }

    func kick(_ v: Double) { velocity += v; NotchDriver.shared.wake() }

    /// Drag-driven: sit exactly where the finger is, no physics.
    func hold(at v: Double) { value = v; target = v; velocity = 0 }

    /// Semi-implicit Euler in fixed 4 ms substeps: stable at 60 or 120 Hz.
    func step(_ dt: Double) {
        let n = max(1, Int((dt / 0.004).rounded(.up))), h = dt / Double(n)
        for _ in 0..<n {
            let pv = velocity
            let a = -k * (value - target) - c * velocity
            velocity += a * h; value += velocity * h
            if let peak = onPeak, pv.sign == direction.sign, velocity.sign != direction.sign, (value - target) * direction > 0 {
                onPeak = nil; peak()
            }
        }
        if isResting { value = target; velocity = 0; if let peak = onPeak { onPeak = nil; peak() } }   // critically damped: fire on arrival
    }

    var isResting: Bool { abs(value - target) < 0.05 && abs(velocity) < 0.05 }
}

enum Motion {
    /// System Reduce Motion, or Gremlo's own setting.
    static var reduce: Bool { NSWorkspaceProxy.reduceMotion || Settings.shared.reduceMotion }
}
