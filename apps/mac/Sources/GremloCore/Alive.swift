import CoreGraphics
import Foundation

// Pets alive (spec R2 §3-6): pure, time-injected logic. The app supplies the clock, the cursor and the RNG.

// MARK: - RNG

/// SplitMix64: small, seedable, the same sequence on every Mac for the same seed.
public struct SeededRNG: RandomNumberGenerator, Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// A seed per local day, so a pet's idle rhythm is the same all day and different tomorrow (spec R2 §3).
    public static func daySeed(_ date: Date, calendar: Calendar = .current) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64(c.year ?? 0) * 10_000 + UInt64(c.month ?? 0) * 100 + UInt64(c.day ?? 0)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

// MARK: - Idle scheduler (spec R2 §3)

public enum Micro: String, Sendable { case sit, yawn }

public struct Quiet: Sendable, Equatable {
    public var holdingLine = false, approvalWaiting = false, inMeeting = false, screenShared = false
    public init(holdingLine: Bool = false, approvalWaiting: Bool = false, inMeeting: Bool = false, screenShared: Bool = false) {
        self.holdingLine = holdingLine; self.approvalWaiting = approvalWaiting; self.inMeeting = inMeeting; self.screenShared = screenShared
    }
    public var any: Bool { holdingLine || approvalWaiting || inMeeting || screenShared }
}

public struct IdleScheduler: Sendable {
    public static let minGap = 25.0, maxGap = 45.0
    public static let weights: [(Micro, Int)] = [(.sit, 3), (.yawn, 2)]
    public static let napAfter = 15 * 60.0, napAfterAtNight = 5 * 60.0

    public private(set) var nextAt: Date
    var rng: SeededRNG

    public init(now: Date, seed: UInt64) {
        rng = SeededRNG(seed: seed)
        nextAt = now
        nextAt = now.addingTimeInterval(gap())
    }

    mutating func gap() -> Double { Self.minGap + rng.unit() * (Self.maxGap - Self.minGap) }

    /// The micro-behaviour due now, or nil. Quiet rules skip a beat but keep the rhythm.
    public mutating func next(now: Date, quiet: Quiet) -> Micro? {
        guard now >= nextAt else { return nil }
        nextAt = now.addingTimeInterval(gap())
        if quiet.any { return nil }
        let total = Self.weights.reduce(0) { $0 + $1.1 }
        var pick = Int(rng.unit() * Double(total))
        for (m, w) in Self.weights { if pick < w { return m }; pick -= w }
        return Self.weights.last?.0
    }

    /// Time to nap: 15 min without an agent event, 5 min at night.
    public static func shouldNap(idleFor seconds: TimeInterval, night: Bool) -> Bool { seconds >= (night ? napAfterAtNight : napAfter) }
}

// MARK: - Gaze (spec R2 §1 row 17)

public struct Gaze: Sendable {
    public static let reach: CGFloat = 300, hysteresis: CGFloat = 12, settle = 3.0
    static let edges: [CGFloat] = [-150, -40, 40, 150]
    public private(set) var frame: Int?

    public init() {}

    /// Frame 0-4 for a horizontal cursor offset (cursor x minus pet centre), or nil when out of reach. A band
    /// change needs the offset to cross the edge by 12 px, so the eyes don't flicker on a boundary.
    public mutating func update(offsetX dx: CGFloat, distance: CGFloat) -> Int? {
        guard distance <= Self.reach else { frame = nil; return nil }
        let raw = Self.band(dx)
        guard let current = frame, current != raw else { frame = raw; return raw }
        let edge = raw > current ? Self.edges[current] : Self.edges[raw]
        if abs(dx - edge) >= Self.hysteresis { frame = raw }
        return frame
    }

    public static func band(_ dx: CGFloat) -> Int {
        if dx < -150 { return 0 }
        if dx < -40 { return 1 }
        if dx <= 40 { return 2 }
        if dx <= 150 { return 3 }
        return 4
    }
}

// MARK: - Physics (spec R2 §4)

public enum Physics {
    public static let gravity: CGFloat = 2400, restitution: CGFloat = 0.35, maxBounces = 3, floorFriction: CGFloat = 0.8
    public static let releaseCap: CGFloat = 3000, dizzyImpact: CGFloat = 1800, grabPress = 0.15
    public static let sulkThrows = 10, sulkWindow = 60.0

    public struct Body: Sendable, Equatable {
        public var x, y, vx, vy: CGFloat   // points; y is height above the floor
        public var bounces = 0
        public var resting = false
        public var dizzy = false
        public init(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat) { self.x = x; self.y = y; self.vx = vx; self.vy = vy }
    }

    /// Release velocity clamped to 3,000 pt/s, keeping its direction.
    public static func release(vx: CGFloat, vy: CGFloat) -> (CGFloat, CGFloat) {
        let speed = (vx * vx + vy * vy).squareRoot()
        guard speed > releaseCap else { return (vx, vy) }
        return (vx / speed * releaseCap, vy / speed * releaseCap)
    }

    /// One integration step between walls `minX...maxX`. On the floor: bounce with restitution (max 3), friction
    /// on each contact, dizzy when the first impact is harder than 1,800 pt/s, then rest.
    public static func step(_ b: inout Body, dt: CGFloat, minX: CGFloat, maxX: CGFloat) {
        guard !b.resting else { return }
        b.vy -= gravity * dt
        b.x += b.vx * dt
        b.y += b.vy * dt
        if b.x < minX { b.x = minX; b.vx = -b.vx * restitution }
        if b.x > maxX { b.x = maxX; b.vx = -b.vx * restitution }
        if b.y <= 0 {
            b.y = 0
            let impact = -b.vy
            if b.bounces == 0 && impact > dizzyImpact { b.dizzy = true }
            b.bounces += 1
            b.vx *= floorFriction
            if b.bounces > maxBounces || impact * restitution < 60 {
                b.vy = 0; b.vx = 0; b.resting = true
            } else {
                b.vy = impact * restitution
            }
        }
    }

    /// While a pet is held: the door locks (it can't be thrown into the notch), the earner lowers the plate and
    /// impressions stop counting until it is back on its feet.
    public struct HeldRules: Equatable, Sendable { public let doorLocked: Bool, plateShown: Bool, countsImpressions: Bool }
    public static func rules(held: Bool) -> HeldRules {
        held ? HeldRules(doorLocked: true, plateShown: false, countsImpressions: false)
             : HeldRules(doorLocked: false, plateShown: true, countsImpressions: true)
    }

    /// What a release does: fly with physics, or with Reduce Motion fade out and back in where it was dropped.
    public enum Release: Equatable, Sendable { case fly(vx: CGFloat, vy: CGFloat), fadeInPlace }
    public static func release(vx: CGFloat, vy: CGFloat, reduceMotion: Bool) -> Release {
        if reduceMotion { return .fadeInPlace }
        let (x, y) = release(vx: vx, vy: vy)
        return .fly(vx: x, vy: y)
    }

    /// A press counts as a grab only after 150 ms, so ordinary clicks still feed hover and annoy.
    public static func isGrab(pressedFor seconds: TimeInterval) -> Bool { seconds >= grabPress }

    /// Ten throws in a minute make the pet sulk (cosmetic).
    public static func sulks(throws times: [Date], now: Date) -> Bool {
        times.filter { now.timeIntervalSince($0) <= sulkWindow }.count >= sulkThrows
    }
}

// MARK: - Social (spec R2 §5)

public enum Meet: String, Sendable { case wave, highFive, chase }

public struct Social: Sendable {
    public static let reach: CGFloat = 60, pairCooldown = 600.0, perHour = 6
    var lastByPair: [String: Date] = [:]
    var recent: [Date] = []
    public init() {}

    static func pairKey(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    /// Two free pets meet when within 60 pt and walking toward each other. Returns the meetup, or nil.
    /// Wave always; then high-five 35%; then chase 15%. A visiting pet only waves.
    public mutating func meet(_ a: (id: String, x: CGFloat, dir: CGFloat, free: Bool, visitor: Bool),
                              _ b: (id: String, x: CGFloat, dir: CGFloat, free: Bool, visitor: Bool),
                              now: Date, quiet: Quiet, rng: inout SeededRNG) -> [Meet]? {
        guard a.free, b.free, !quiet.any, abs(a.x - b.x) <= Self.reach else { return nil }
        let towards = (b.x - a.x) * a.dir > 0 && (a.x - b.x) * b.dir > 0
        guard towards else { return nil }
        let key = Self.pairKey(a.id, b.id)
        if let last = lastByPair[key], now.timeIntervalSince(last) < Self.pairCooldown { return nil }
        recent = recent.filter { now.timeIntervalSince($0) < 3600 }
        guard recent.count < Self.perHour else { return nil }
        lastByPair[key] = now
        recent.append(now)
        var out: [Meet] = [.wave]
        if a.visitor || b.visitor { return out }
        if rng.unit() < 0.35 { out.append(.highFive) }
        if rng.unit() < 0.15 { out.append(.chase) }
        return out
    }
}

// MARK: - Context (spec R2 §6)

public enum Context {
    /// 23:00-06:00 local.
    public static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: date)
        return h >= 23 || h < 6
    }

    public enum Power: Equatable, Sendable { case normal, low, critical }
    /// Unplugged below 20%: sit more at half frame rate. Below 10%: go home and sleep. Plugged in: normal.
    public static func power(percent: Int?, onBattery: Bool) -> Power {
        guard onBattery, let p = percent else { return .normal }
        if p < 10 { return .critical }
        if p < 20 { return .low }
        return .normal
    }
    public static func frameRateFactor(_ p: Power) -> Double { p == .low ? 0.5 : 1 }

    /// The first session of the local day plays the species signature move once.
    public static func firstSessionToday(lastSignature: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last = lastSignature else { return true }
        return !calendar.isDate(last, inSameDayAs: now)
    }
}

// MARK: - Tool props (spec R2 §6, R4 §2)

public enum Prop: Int, CaseIterable, Sendable { case wrench = 0, magnifier, flask, terminal, globe, notepad }

public enum Tools {
    /// Test runners, matched locally on a Bash command. Users can add patterns.
    public static let runners: [String] = [
        #"^(npm|pnpm|yarn|bun)\s+(run\s+)?test\b"#, #"^npx\s+(vitest|jest|mocha)\b"#, #"^vitest\b"#, #"^jest\b"#, #"^pytest\b"#,
        #"^python3?\s+-m\s+pytest\b"#, #"^go\s+test\b"#, #"^cargo\s+test\b"#, #"^forge\s+test\b"#, #"^mix\s+test\b"#,
        #"^(bundle\s+exec\s+)?rspec\b"#, #"^dotnet\s+test\b"#, #"^swift\s+test\b"#, #"^mocha\b"#,
    ]

    /// The runner a command starts with, or nil. Leading env assignments and `cd x &&` are skipped.
    public static func runner(_ command: String, extra: [String] = []) -> String? {
        var cmd = command.trimmingCharacters(in: .whitespaces)
        if let r = cmd.range(of: #"^(cd\s+\S+\s*&&\s*)+"#, options: .regularExpression) { cmd.removeSubrange(r) }
        while let r = cmd.range(of: #"^[A-Z_][A-Z0-9_]*=\S*\s+"#, options: .regularExpression) { cmd.removeSubrange(r) }
        for p in runners + extra where cmd.range(of: p, options: .regularExpression) != nil {
            return cmd.split(separator: " ").prefix(2).joined(separator: " ")
        }
        return nil
    }

    /// The prop for a tool call, or nil for an unknown tool (no prop rather than a wrong one).
    public static func prop(tool: String, command: String? = nil) -> Prop? {
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch", "edit_file": return .wrench
        case "Read", "Grep", "Glob", "LS", "read", "search", "read_file", "grep_search": return .magnifier
        case "WebFetch", "WebSearch", "web_search": return .globe
        case "TodoWrite", "update_plan", "todo_write": return .notepad
        case "Bash", "shell", "run_terminal_cmd":
            if let c = command, runner(c) != nil { return .flask }
            return .terminal
        default: return nil
        }
    }
}
