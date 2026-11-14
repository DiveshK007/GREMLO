import CoreGraphics
import Foundation

// Notch feel numbers (docs/design/notch-feel/NOTCH_FEEL.md): the shape, lean, stagger, idle life and rim colours.
// Pure, so the Mac app draws exactly what the tests check.

/// The notch as one path with ears, in unflipped coordinates: the top edge sits at `top` and the body hangs down.
public struct NotchGeometry: Equatable, Sendable {
    public var width: CGFloat, height: CGFloat, radius: CGFloat
    public var ear: CGFloat = 10       // the inverted corners where the notch meets the bezel
    public var bulge: CGFloat = 0      // 0...1: the sides bow out while opening
    public init(width: CGFloat, height: CGFloat, radius: CGFloat, ear: CGFloat = 10, bulge: CGFloat = 0) {
        self.width = width; self.height = height; self.radius = radius; self.ear = ear; self.bulge = bulge
    }

    public func path(centerX cx: CGFloat, top: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let l = cx - width / 2, r = cx + width / 2, h = max(height, 1)
        let rad = max(0, min(radius, h / 2, width / 4)), ear = min(self.ear, h / 2)
        let bow = bulge * min(10, width * 0.02)
        func y(_ d: CGFloat) -> CGFloat { top - d }  // d = distance down from the top edge
        p.move(to: CGPoint(x: l - ear, y: y(0)))
        p.addQuadCurve(to: CGPoint(x: l, y: y(ear)), control: CGPoint(x: l, y: y(0)))
        p.addCurve(to: CGPoint(x: l, y: y(h - rad)), control1: CGPoint(x: l - bow, y: y(h * 0.35)), control2: CGPoint(x: l - bow, y: y(h * 0.7)))
        p.addQuadCurve(to: CGPoint(x: l + rad, y: y(h)), control: CGPoint(x: l, y: y(h)))
        p.addLine(to: CGPoint(x: r - rad, y: y(h)))
        p.addQuadCurve(to: CGPoint(x: r, y: y(h - rad)), control: CGPoint(x: r, y: y(h)))
        p.addCurve(to: CGPoint(x: r, y: y(ear)), control1: CGPoint(x: r + bow, y: y(h * 0.7)), control2: CGPoint(x: r + bow, y: y(h * 0.35)))
        p.addQuadCurve(to: CGPoint(x: r + ear, y: y(0)), control: CGPoint(x: r, y: y(0)))
        p.closeSubpath()
        return p
    }
}

public enum NotchFeel {
    /// #4 lean: weighted distance from the notch's top centre; within 140 pt the notch grows up to +18 w / +4 h and
    /// shifts up to 8 pt toward the cursor. Under 34 pt is hover, past 70 pt leaves it.
    public struct Lean: Equatable, Sendable { public var distance, near, shift, growW, growH: CGFloat }
    public static func lean(dx: CGFloat, dy: CGFloat) -> Lean {
        let d = hypot(dx * 0.6, dy), near = max(0, 1 - d / 140)
        return Lean(distance: d, near: near, shift: max(-1, min(1, dx / 200)) * 8 * near, growW: 18 * near, growH: 4 * near)
    }
    public static let hoverEnter: CGFloat = 34, hoverLeave: CGFloat = 70
    public static let hoverSize = (w: 236.0, h: 38.0)

    /// #3 stagger: rows fade in 60 ms after the shape starts, 45 ms apart; nothing staggers under Reduce Motion.
    public static func rowDelay(_ i: Int, reduce: Bool) -> Double { reduce ? 0 : 0.06 + 0.045 * Double(i) }
    public static let rowFade = 0.18, rowSlide: CGFloat = 6, contentOut = 0.08

    /// #2 squash: kicked wide on opening, tall on closing; scale is 1 -/+ 0.03 x squash around the top centre.
    public static let squashOpen = -2.2, squashClose = 1.4, squashScale = 0.03
    /// #5 press dent.
    public static let pressScale = 0.955

    /// A size change counts as opening when the area grows by more than a sliver (it gets the open spring and the peak tap).
    public static func isOpening(from: (w: Double, h: Double), to: (w: Double, h: Double)) -> Bool { to.w * to.h > from.w * from.h + 200 }

    /// Corner radius per state (spec sizes table): small pills stay round, cards get the big radius.
    public static func radius(_ s: LiveState) -> Double {
        switch s {
        case .rest: return 12
        case .think: return 13
        case .peek, .egg, .sleep, .focus, .meeting, .offline: return 14
        case .visitor: return 16
        case .done, .ticker: return 24
        case .drop: return 30
        case .quick: return 24
        case .knock, .queue, .stuck: return 28
        case .room: return 34
        }
    }

    /// #13 rim colours: colour only, never a logo.
    public enum Rim: Sendable { case off, solid, flow }
    public static func rim(_ s: LiveState) -> Rim {
        switch s {
        case .think: return .flow
        case .knock, .queue, .done, .ticker, .stuck, .room: return .solid
        default: return .off
        }
    }
    public static func agentColor(_ agent: String) -> String {
        let a = agent.lowercased()
        if a.contains("claude") { return "#D97757" }
        if a.contains("codex") { return "#10A37F" }
        if a.contains("cursor") { return "#4C8DFF" }
        return "#FF5A3C"
    }
    public static let doneColor = "#8FD14F", failColor = "#FF5A3C", mergeColor = "#B48CFF", batteryColor = "#FFB020"

    /// #7 rubber band: follows the finger, then resists. Past 130 pt the room opens; an upward flick over 500 pt/s
    /// dismisses a big state.
    public static func band(_ dy: CGFloat) -> CGFloat { dy <= 0 ? 0 : dy * 0.55 / (1 + dy / 320) * 2 }
    public static let pullThreshold: CGFloat = 130, flickSpeed: CGFloat = 500
    /// #8 one detent per 40 pt of scroll; the content slides 30 pt the same way.
    public static let detent: CGFloat = 40, detentSlide: CGFloat = 30
    /// #9 without Force Touch, holding this long opens the quick actions.
    public static let quickHold = 0.48
    /// #21 heartbeat while an approval waits: every 1.4 s, for 30 s at most.
    public static let heartbeatEvery = 1.4, heartbeatFor = 30.0
    /// #14 particles: a burst from the bottom edge, capped by the budget (140, or 50 in Low Power Mode).
    public enum Burst: Sendable { case confetti, sparks, smoke, sweat }
    public static func particles(_ b: Burst, lowPower: Bool) -> Int {
        let want: Int
        switch b { case .confetti: want = 60; case .sparks: want = 36; case .smoke: want = 14; case .sweat: want = 6 }
        return min(want, lowPower ? 50 : 140)
    }

    /// #16 idle life: every 20-40 s at rest one small action for 2.2 s; the night row from 22:00 to 06:00.
    public static let idleEvery = 20.0...40.0, idleHold = 2.2
    public static let idleSize = (w: 240.0, h: 46.0)
    public static func idleRow(hour: Int, pick: Int) -> Row {
        if hour >= 22 || hour < 6 { return .night }
        return [Row.yawn, .peek, .edgepeek, .gaze][abs(pick) % 4]
    }
    public static func idleAllowed(state: LiveState, screenShared: Bool, inMeeting: Bool, focus: Bool) -> Bool {
        state == .rest && !screenShared && !inMeeting && !focus
    }
}
