import Foundation

// Theme, sound and haptics (spec R2 §7-8, HAPTICS.md): pure rules, clock injected.

// MARK: - Theme (spec R2 §7)

public enum ThemeSetting: String, CaseIterable, Sendable { case system, light, dark }
public enum Mode: String, Sendable { case light, dark }

public enum Theme {
    public static func resolve(_ s: ThemeSetting, systemIsDark: Bool) -> Mode {
        switch s {
        case .system: return systemIsDark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
    }
    /// Accent-coloured text: the accent on ink, the paper-safe shade on paper. Fills and the pet keep the accent.
    public static func accentText(_ s: Species, _ m: Mode) -> String { m == .dark ? s.accent : s.paperSafe }
    public static func background(_ m: Mode) -> String { m == .dark ? Palette.ink : Palette.paper }
    public static func surface(_ m: Mode) -> String { m == .dark ? Palette.carbon : Palette.bone }
    /// The notch and Notch Live are always black, whatever the theme.
    public static let notch = "#000000"
}

// MARK: - Sound (spec R2 §8)

public enum SoundLevel: Int, CaseIterable, Sendable, Comparable {
    case off = 0, approvalsOnly, petSounds, everything
    public static func < (a: SoundLevel, b: SoundLevel) -> Bool { a.rawValue < b.rawValue }
    public static let `default` = SoundLevel.approvalsOnly
    public var title: String {
        switch self {
        case .off: return "Off"
        case .approvalsOnly: return "Approvals only"
        case .petSounds: return "Pet sounds"
        case .everything: return "Everything"
        }
    }
}

public struct SilenceGate: Sendable, Equatable {
    public var screenShared = false, inMeeting = false, focus = false, fullScreenVideo = false
    public init(screenShared: Bool = false, inMeeting: Bool = false, focus: Bool = false, fullScreenVideo: Bool = false) {
        self.screenShared = screenShared; self.inMeeting = inMeeting; self.focus = focus; self.fullScreenVideo = fullScreenVideo
    }
    public var silent: Bool { screenShared || inMeeting || focus || fullScreenVideo }
}

public enum Sounds {
    /// The lowest level at which each sound plays.
    public static let level: [String: SoundLevel] = {
        var m: [String: SoundLevel] = ["approval": .approvalsOnly]
        for s in ["allow", "deny", "celebrate", "fail", "meal", "door-open", "door-close", "hatch", "offline", "focus-start", "focus-end"] { m[s] = .petSounds }
        for s in ["whoosh", "thud", "boing", "dizzy", "stomp", "high-five", "yawn", "snore", "poke-1", "poke-2", "poke-3", "poke-4", "poke-5"] { m[s] = .everything }
        return m
    }()

    /// The file for a moment, by the spec's event map.
    public static let events: [String: String] = [
        "PermissionRequest": "approval", "allow": "allow", "deny": "deny", "door.open": "door-open", "door.close": "door-close",
        "Stop": "celebrate", "StopFailure": "fail", "meal": "meal", "hatch": "hatch", "throw": "whoosh", "land": "thud",
        "bounce": "boing", "dizzy": "dizzy", "stomp": "stomp", "meet": "high-five", "focus.start": "focus-start",
        "focus.end": "focus-end", "yawn": "yawn", "snore": "snore", "offline": "offline",
    ]

    /// Volume for a sound, relative to the system alert volume. Snore plays at 30%.
    public static func volume(_ name: String) -> Float { name == "snore" ? 0.3 : 1 }

    /// Whether `name` plays: never for the sponsored line, never behind the silence gate, else by level.
    public static func plays(_ name: String, level: SoundLevel, gate: SilenceGate, forSponsoredLine: Bool = false) -> Bool {
        if forSponsoredLine || gate.silent || level == .off { return false }
        if name.hasPrefix("voice-") { return level >= .petSounds }
        guard let need = Self.level[name] else { return false }
        return level >= need
    }

    /// The nth click's poke (1-5), the 5th in 6 s being the stomp instead.
    public static func poke(click n: Int) -> String { n >= 5 ? "stomp" : "poke-\(max(1, min(n, 5)))" }
}

/// Voices play only alongside a real model bubble (one with a request ID), at most once every 20 s.
public struct VoiceLimiter: Sendable {
    public static let gap = 20.0
    var last = Date.distantPast
    public init() {}
    public mutating func voice(species: String, mood: String, requestId: String?, now: Date) -> String? {
        guard let id = requestId, !id.isEmpty, now.timeIntervalSince(last) >= Self.gap else { return nil }
        last = now
        let kind = mood == "happy" ? "happy" : mood == "grumpy" ? "grumpy" : "say"
        return "voice-\(species)-\(kind)"
    }
}

// MARK: - Haptics (HAPTICS.md)

public enum Haptic: String, CaseIterable, Sendable { case tick, snap, boop, purr, knock, thud, stomp, allow, deny, hatch }
public enum HapticPattern: String, Sendable { case alignment, levelChange, generic }
public enum HapticLevel: String, CaseIterable, Sendable { case on, subtle, off }

public enum Haptics {
    public static let recipes: [Haptic: [(HapticPattern, TimeInterval)]] = [
        .tick: [(.alignment, 0)], .snap: [(.levelChange, 0)], .boop: [(.generic, 0)],
        .purr: [(.alignment, 0), (.alignment, 0.09), (.alignment, 0.18), (.alignment, 0.27)],
        .knock: [(.generic, 0), (.generic, 0.12)], .thud: [(.levelChange, 0), (.generic, 0.04)],
        .stomp: [(.levelChange, 0), (.levelChange, 0.07), (.levelChange, 0.14)],
        .allow: [(.levelChange, 0)], .deny: [(.generic, 0), (.generic, 0.08)],
        .hatch: [(.alignment, 0), (.alignment, 0.15), (.alignment, 0.30), (.levelChange, 0.60)],
    ]

    /// The Mac map: each moment a finger is on the pad, and its haptic. Celebrate has none on the Mac.
    public static let macMap: [String: Haptic] = [
        "hover.pet": .purr, "click.pet": .boop, "click.fifth": .stomp, "grab": .snap, "drag.titlebar": .tick,
        "drag.notch": .snap, "land.fingerDown": .thud, "notch.hover": .tick, "notch.pin": .snap, "room.third": .tick,
        "room.open": .snap, "swipe.agent": .tick, "answer.allow": .allow, "answer.deny": .deny, "closet.snap": .tick,
    ]
}

/// Decides whether a haptic plays now: the level, 100 ms between patterns, purr at most every 10 s, and nothing
/// during a screen share or while a sponsored line is up. Haptics are never the only signal for anything.
public struct HapticGate: Sendable {
    public var level: HapticLevel = .on
    var last = Date.distantPast, lastPurr = Date.distantPast, lastTick = Date.distantPast
    public init(level: HapticLevel = .on) { self.level = level }

    public mutating func play(_ h: Haptic, now: Date, screenShared: Bool, lineUp: Bool) -> [(HapticPattern, TimeInterval)]? {
        guard level != .off, !screenShared, !lineUp else { return nil }
        if level == .subtle && h != .tick { return nil }
        // texture ticks may be dense but never closer than 35 ms (notch feel #20); every other pattern keeps 100 ms
        if h == .tick {
            guard now.timeIntervalSince(lastTick) >= 0.035 else { return nil }
            lastTick = now
            return Haptics.recipes[h]
        }
        guard now.timeIntervalSince(last) >= 0.1 else { return nil }
        if h == .purr { guard now.timeIntervalSince(lastPurr) >= 10 else { return nil }; lastPurr = now }
        last = now
        return Haptics.recipes[h]
    }
}
