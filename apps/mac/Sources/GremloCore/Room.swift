import Foundation
import CoreGraphics
import CoreText

// Round 4 §11-15 and base §9: the room, the guestbook, focus sessions (R2 §12), the privacy rules that duck the
// pets, the line limiter, stream mode's overlay payload and the weekly postcard. Stars only; no money here.

// MARK: - The room (R4 §11)

public struct Furniture: Sendable, Equatable {
    public let id: String, stars: Int, x: Int, y: Int, prop: String
    public enum Use: Sendable, Equatable { case none, standsOn, bops, naps, watches }
    public let use: Use
}

public enum Room {
    public static let size = (w: 180, h: 104)   // units
    public static let items: [Furniture] = [
        Furniture(id: "lights", stars: 9, x: 74, y: 6, prop: "f-lights", use: .none),
        Furniture(id: "poster", stars: 5, x: 120, y: 20, prop: "f-poster", use: .none),
        Furniture(id: "shelf", stars: 12, x: 18, y: 26, prop: "f-shelf", use: .none),
        Furniture(id: "rug", stars: 8, x: 77, y: 90, prop: "f-rug", use: .standsOn),
        Furniture(id: "lamp", stars: 10, x: 36, y: 76, prop: "f-lamp", use: .none),
        Furniture(id: "radio", stars: 10, x: 52, y: 81, prop: "f-records", use: .bops),
        Furniture(id: "beanbag", stars: 14, x: 112, y: 84, prop: "f-beanbag", use: .naps),
        Furniture(id: "fishbowl", stars: 15, x: 136, y: 82, prop: "f-fishbowl", use: .watches),
        Furniture(id: "plant", stars: 6, x: 158, y: 79, prop: "f-plant", use: .none),
    ]
    public static func item(_ id: String) -> Furniture? { items.first { $0.id == id } }

    /// Takes a piece for its stars, from the same ledger as the Closet. It goes straight into the room.
    @discardableResult
    public static func take(_ id: String, _ p: inout PetProgress, at: Date) -> Bool {
        guard let f = item(id), !p.furniture.contains(id), p.stars >= f.stars else { return false }
        p.ledger.append(LedgerRow(reason: "room: \(id)", amount: -f.stars, ref: "room-\(id)", at: at))
        p.furniture.append(id)
        p.placed.append(id)
        return true
    }

    /// Clicking a placed piece puts it away (you keep it); clicking again puts it back in its fixed spot.
    public static func toggle(_ id: String, _ p: inout PetProgress) {
        guard p.furniture.contains(id) else { return }
        if p.placed.contains(id) { p.placed.removeAll { $0 == id } } else { p.placed.append(id) }
    }

    /// Where the pet goes in the room for what's happening: the beanbag at night, the radio while an agent works,
    /// the fishbowl when idle, else the rug (or the middle of the floor).
    public static func petSpot(placed: [String], night: Bool, agentWorking: Bool) -> (item: Furniture?, row: Row) {
        func has(_ u: Furniture.Use) -> Furniture? { items.first { $0.use == u && placed.contains($0.id) } }
        if night, let b = has(.naps) { return (b, .night) }
        if agentWorking, let r = has(.bops) { return (r, .celebrate) }
        if let f = has(.watches) { return (f, .gaze) }
        return (has(.standsOn), .sit)
    }
}

// MARK: - Guestbook (R4 §12)

public struct GuestbookEntry: Codable, Equatable, Sendable {
    public let pet: String, species: String, stage: String, outfit: [String], at: Date
    public init(pet: String, species: String, stage: String, outfit: [String], at: Date) {
        self.pet = pet; self.species = species; self.stage = stage; self.outfit = outfit; self.at = at
    }

    /// Exactly what a visit may carry: no messages, no owner names. Unknown fields are dropped.
    public static func from(_ visit: [String: Any], at: Date) -> GuestbookEntry? {
        guard let name = visit["name"] as? String, let species = visit["species"] as? String, Roster.species(species) != nil else { return nil }
        let stage = (visit["stage"] as? String).flatMap { s in Stage.allCases.first { "\($0)" == s } }.map { "\($0)" } ?? "hatchling"
        let outfit = (visit["outfit"] as? [String] ?? []).filter { Closet.prices[$0] != nil || Closet.milestones[$0] != nil }
        return GuestbookEntry(pet: String(name.prefix(24)), species: species, stage: stage, outfit: Array(outfit.prefix(3)), at: at)
    }
    public static let visitSeconds = 20.0
}

// MARK: - Focus (R2 §12)

public struct FocusSession: Codable, Equatable, Sendable {
    public static let durations = [25, 50, 90]
    public let start: Date, minutes: Int
    public init(start: Date, minutes: Int) { self.start = start; self.minutes = minutes }
    public var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
    public func remaining(_ now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
    public func finished(_ now: Date) -> Bool { now >= end }
    /// The ring: 0 at the start, 1 at the end.
    public func progress(_ now: Date) -> Double { min(1, max(0, now.timeIntervalSince(start) / (Double(minutes) * 60))) }
    public func label(_ now: Date) -> String { let s = Int(remaining(now)); return "\(s / 60):\(String(format: "%02d", s % 60))" }
}

// MARK: - Privacy rules (base §9): always on, no setting

public enum Duck: Equatable, Sendable {
    case none, intoNotch, sleep, home, hidden

    /// Screen shared or recorded: duck into the notch (unless stream mode, where the user chose to show the pet).
    /// Meeting: sleep. Focus: home. Full screen: hidden.
    public static func decide(screenShared: Bool, inMeeting: Bool, focus: Bool, fullScreen: Bool, streamMode: Bool) -> Duck {
        if screenShared && !streamMode { return .intoNotch }
        if fullScreen { return .hidden }
        if inMeeting { return .sleep }
        if focus { return .home }
        return .none
    }
}

/// At most 12 lines an hour, never the same brand twice in a row.
public struct LineLimiter: Sendable {
    public static let perHour = 12
    var shown: [Date] = []
    var lastBrand: String?
    public init() {}

    public func allows(brand: String, now: Date) -> Bool {
        shown.filter { now.timeIntervalSince($0) < 3600 }.count < Self.perHour && (lastBrand == nil || lastBrand != brand || brand.isEmpty)
    }
    public mutating func record(brand: String, now: Date) {
        shown = shown.filter { now.timeIntervalSince($0) < 3600 } + [now]
        lastBrand = brand
    }
    /// A line from another brand (or nothing at all) shown since lets the same brand return.
    public mutating func clearBrand() { lastBrand = nil }
}

// MARK: - Stream mode (R4 §13)

public enum StreamOverlay {
    /// What the OBS overlay gets: the pet, its mood and the tool count. An approval reads "waiting on me", never the
    /// command. No sponsored line, ever.
    public static func payload(name: String, species: String, stage: Stage, mood: String, tools: Int, waiting: Bool) -> [String: Any] {
        ["name": name, "species": species, "stage": "\(stage)", "mood": mood, "tools": tools, "status": waiting ? "waiting on me" : (tools > 0 ? "working" : "resting")]
    }
    /// While on, the plate is off and sightings don't count (a stream has many viewers, not one).
    public static func plateAllowed(streamMode: Bool) -> Bool { !streamMode }
}

// MARK: - Weekly postcard (R4 §15)

public struct WeekCounts: Codable, Equatable, Sendable {
    public var runs = 0, bugs = 0
    public var trick: String?
    public var outfit: [String] = []
    public init() {}
}

public enum Postcard {
    /// Sunday 18:00 local.
    public static func due(now: Date, lastSent: Date?, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour], from: now)
        guard c.weekday == 1, (c.hour ?? 0) >= 18 else { return false }
        return lastSent.map { now.timeIntervalSince($0) > 6 * 86400 } ?? true
    }

    /// The card's text: counts and the outfit only. No code, repo or file names, prompts, earnings or sponsors.
    public static func lines(name: String, species: String, w: WeekCounts) -> [String] {
        var out = ["\(name) the \(species)", "This week: watched \(w.runs) run\(w.runs == 1 ? "" : "s"), caught \(w.bugs) bug\(w.bugs == 1 ? "" : "s")."]
        if let t = w.trick { out.append("Learned a trick: \(t).") }
        out.append(w.outfit.isEmpty ? "Wore nothing fancy." : "Wore: \(w.outfit.joined(separator: ", ")).")
        return out
    }

    /// Renders the card as an image: the pet frame on the left, the lines on the right.
    public static func render(lines: [String], pet: CGImage?, accent: CGColor, scale: CGFloat = 2) -> CGImage? {
        let w = 600 * scale, h = 300 * scale
        guard let ctx = Images.context(Int(w), Int(h)) else { return nil }
        ctx.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(accent)
        ctx.fill(CGRect(x: 0, y: h - 10 * scale, width: w, height: 10 * scale))
        if let pet {
            ctx.interpolationQuality = .none
            let ph = 200 * scale, pw = ph * CGFloat(pet.width) / CGFloat(pet.height)
            ctx.draw(pet, in: CGRect(x: 30 * scale, y: 40 * scale, width: pw, height: ph))
        }
        var y = h - 70 * scale
        for (i, l) in lines.enumerated() {
            let font = Fonts.inter((i == 0 ? 26 : 17) * scale, weight: i == 0 ? 700 : 500)
            let attr = NSAttributedString(string: l, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                                     NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 250 * scale, y: y)
            CTLineDraw(line, ctx)
            y -= (i == 0 ? 46 : 32) * scale
        }
        return ctx.makeImage()
    }
}
