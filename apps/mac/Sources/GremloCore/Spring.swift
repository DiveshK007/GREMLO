import Foundation

// Notch feel (docs/design/notch-feel/NOTCH_FEEL.md §1, §3): a damped spring you can retarget mid-flight. Velocity
// carries over, so grabbing the notch while it opens feels continuous. `onPeak` fires on the step where the overshoot
// is biggest (velocity flips sign while past the target): the frame the haptic lands on.

public struct SpringParams: Equatable, Sendable {
    public var response: Double   // seconds for one oscillation
    public var damping: Double    // 0 wobbles forever, 1 critically damped (no overshoot)
    public init(response: Double, damping: Double) { self.response = response; self.damping = damping }

    public static let open    = SpringParams(response: 0.42, damping: 0.70)  // ~6% overshoot, haptic on the peak
    public static let close   = SpringParams(response: 0.30, damping: 0.88)
    public static let press   = SpringParams(response: 0.14, damping: 0.60)  // the dent
    public static let release = SpringParams(response: 0.22, damping: 0.45)  // springs back past 100% once
    public static let lean    = SpringParams(response: 0.25, damping: 0.80)
    public static let squash  = SpringParams(response: 0.22, damping: 0.45)
    public static let pull    = SpringParams(response: 0.35, damping: 0.70)

    /// Height lands a beat after width, so the shape feels heavy.
    public var heavier: SpringParams { SpringParams(response: response + 0.03, damping: damping) }
    /// Reduce Motion: no overshoot, 0.2 s at most.
    public var reduced: SpringParams { SpringParams(response: min(response, 0.2), damping: 1) }
    /// Stiffness and damping for mass 1 (what CASpringAnimation takes too).
    public var stiffness: Double { pow(2 * .pi / response, 2) }
    public var dampingCoefficient: Double { 4 * .pi * damping / response }
}

public enum Motion {
    /// System Reduce Motion (set by the app); springs read it whenever their parameters change.
    public static var reduce = false
}

public final class Spring {
    public private(set) var value: Double
    public private(set) var velocity: Double = 0
    public private(set) var target: Double
    private var k = 0.0, c = 0.0
    private var onPeak: (() -> Void)?
    private var direction = 1.0
    /// Called whenever the spring is set moving, so the frame clock can wake.
    public var wake: (() -> Void)?

    public init(_ value: Double, _ p: SpringParams = .open) {
        self.value = value; target = value; set(p)
    }

    public func set(_ p: SpringParams) {
        let p = Motion.reduce ? p.reduced : p
        k = p.stiffness; c = p.dampingCoefficient
    }

    public func animate(to t: Double, _ p: SpringParams? = nil, onPeak: (() -> Void)? = nil) {
        if let p { set(p) }
        target = t
        self.onPeak = onPeak
        direction = t < value ? -1 : 1
        if !isResting || onPeak != nil { wake?() }
    }

    public func kick(_ v: Double) { velocity += v; wake?() }

    /// Drag-driven: sit exactly where the finger is.
    public func hold(at v: Double) { value = v; target = v; velocity = 0 }

    /// Semi-implicit Euler in fixed 4 ms substeps: the same curve at 60 or 120 Hz.
    public func step(_ dt: Double) {
        let n = max(1, Int((dt / 0.004).rounded(.up))), h = dt / Double(n)
        var flipped = false
        for _ in 0..<n {
            let pv = velocity
            (value, velocity) = Self.advance(value, velocity, target: target, k: k, c: c, h: h)
            if pv * direction > 0, velocity * direction <= 0, (value - target) * direction > 0 { flipped = true }
        }
        // The tap lands with the drawn frame that shows the overshoot. Frames are samples: if the turn-around happened
        // inside this frame, this frame is the highest; if it happens inside the next one, this frame is the highest
        // only when the next one would draw lower, which is checked by running the next frame ahead of time.
        if let peak = onPeak, (value - target) * direction > 0 {
            var next = (value, velocity)
            if !flipped { for _ in 0..<n { next = Self.advance(next.0, next.1, target: target, k: k, c: c, h: h) } }
            if flipped || (next.0 - value) * direction < 0 { onPeak = nil; peak() }
        }
        if isResting {
            value = target; velocity = 0
            if let peak = onPeak { onPeak = nil; peak() }  // critically damped: it lands on arrival
        }
    }

    private static func advance(_ x: Double, _ v: Double, target: Double, k: Double, c: Double, h: Double) -> (Double, Double) {
        let nv = v + (-k * (x - target) - c * v) * h
        return (x + nv * h, nv)
    }

    public var isResting: Bool { abs(value - target) < 0.05 && abs(velocity) < 0.05 }
}
