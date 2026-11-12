import Foundation

// The eight original species (spec D §1-2). The active pet lends the interface its accent; on paper, text uses
// the paper-safe shade. None are for sale; none unlock from daily opens or streaks.

public struct Species: Sendable, Equatable {
    public let id: String          // pack folder, assets/pets/<id>
    public let name: String
    public let kind: String
    public let accent: String      // fills, the pet, accent text on ink
    public let paperSafe: String   // accent text on paper
    public let starter: Bool
    public let unlock: String      // shown on a locked species, never a price
    public let voice: String       // tunes the model prompt for bubbles and the diary
    public let signature: String   // the signature move and when it fires
}

public enum Roster {
    public static let all: [Species] = [
        Species(id: "notchi", name: "Notchi", kind: "bean", accent: "#FF5A3C", paperSafe: "#C1442D", starter: true,
                unlock: "starter", voice: "plain-spoken: \"on it.\"", signature: "big stretch, on Stop after a run over 20 min"),
        Species(id: "notchi-pip", name: "Pip", kind: "bird", accent: "#FFC93C", paperSafe: "#876A1F", starter: true,
                unlock: "starter", voice: "chirpy: \"tests passed!\"", signature: "chirp, when tests pass"),
        Species(id: "notchi-moss", name: "Moss", kind: "sprout", accent: "#8FD14F", paperSafe: "#52792D", starter: true,
                unlock: "starter", voice: "calm: \"slow and steady.\"", signature: "bloom, every 10th meal"),
        Species(id: "notchi-gloop", name: "Gloop", kind: "slime", accent: "#2ED3B7", paperSafe: "#1B7C6B", starter: false,
                unlock: "a session over an hour", voice: "patient: \"mhm. still here.\"", signature: "split, on Stop with zero failures"),
        Species(id: "notchi-byte", name: "Byte", kind: "robot", accent: "#4CC9FF", paperSafe: "#2C7696", starter: false,
                unlock: "1,000 tool calls watched", voice: "terse caps: \"EXEC OK.\"", signature: "glitch, when tests fail"),
        Species(id: "notchi-puff", name: "Puff", kind: "cloud", accent: "#8FA8FF", paperSafe: "#5B6BA3", starter: false,
                unlock: "the agent's first failed run", voice: "soft, melancholy", signature: "rain, on StopFailure"),
        Species(id: "notchi-wisp", name: "Wisp", kind: "flame", accent: "#B48CFF", paperSafe: "#7C60AF", starter: false,
                unlock: "any pet thriving 7 days", voice: "quiet, poetic", signature: "flare, on a meal that raises mood"),
        Species(id: "notchi-tako", name: "Tako", kind: "octopus", accent: "#FF7AB6", paperSafe: "#AA5179", starter: false,
                unlock: "secret", voice: "cheeky", signature: "ink squirt, on the 5th click in 6 s"),
    ]

    public static let defaultId = "notchi"
    public static func species(_ id: String) -> Species? { all.first { $0.id == id } }
}

/// Accessory slots (spec R3 §4): head x9, face x2, neck x1. Drawn neck, then face, then head; one item per slot.
public enum Slot: Int, CaseIterable, Sendable, Comparable {
    case neck = 0, face, head
    public static func < (a: Slot, b: Slot) -> Bool { a.rawValue < b.rawValue }
    public static func of(_ item: String) -> Slot {
        switch item {
        case "glasses", "shades": return .face
        case "scarf": return .neck
        default: return .head
        }
    }
}

// MARK: - Colour

public struct RGB: Equatable, Sendable {
    public let r, g, b: Double  // 0...1
    public init?(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
    }
    /// WCAG 2.x relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    /// WCAG contrast ratio between two colours, 1...21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }
}

public enum Palette {
    public static let ink = "#0B0B0B", carbon = "#141414", graphite = "#1F1F1F", bone = "#E9E6DF", paper = "#F4F2ED"
}
