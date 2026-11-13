import Foundation

// Growing up (spec D §2, §6-8; R3 §3-4): stages from meals, the stars ledger and the Closet, hatching, species
// unlocks, one earner and many companions, the diary payload and the certificate. Stars are earned only: no money
// appears anywhere in this file, and a test fails if it ever does.

// MARK: - Stages (spec D §6)

public enum Stage: Int, Codable, CaseIterable, Sendable, Comparable {
    case egg = 0, hatchling, buddy, elder
    public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }

    /// Egg until hatched; then 0-9 meals hatchling, 10-49 buddy, 50+ elder. Never goes backwards.
    public static func from(meals: Int, hatched: Bool, previous: Stage = .egg) -> Stage {
        guard hatched else { return max(previous, .egg) }
        let s: Stage = meals >= 50 ? .elder : meals >= 10 ? .buddy : .hatchling
        return max(s, previous)
    }
    /// The evolve row frame for the stage (0 egg, 3-4 hatchling, 5 elder).
    public var evolveFrame: Int { switch self { case .egg: return 0; case .hatchling: return 3; case .buddy: return 4; case .elder: return 5 } }
}

// MARK: - The stars ledger (spec R3 §4)

public struct LedgerRow: Codable, Equatable, Sendable {
    public let reason: String
    public let amount: Int      // stars; negative for a Closet or room item
    public let ref: String      // a receipt or event id; each ref counts once
    public let at: Date
}

public struct PetProgress: Codable, Equatable, Sendable {
    public var starter: String?
    public var hatchedAt: Date?
    public var firstAgent: String?
    public var name = "Mochi"
    public var stage = Stage.egg
    public var meals: [String] = []            // receipt ids (settlement txs that fed the compute budget)
    public var toolCalls = 0
    public var longestSession: TimeInterval = 0
    public var failedRuns = 0
    public var stomps = 0
    public var thrivingDays: [String] = []     // local days the pet was thriving
    public var approvalsAnswered = 0
    public var celebrations = 0
    public var focusSessions = 0
    public var reviewsAnswered = 0
    public var maxSessionTools = 0             // most tool calls in one session (juggle)
    public var releaseTags = 0                 // release tags seen by the git hook (moonwalk)
    public var bugJar = 0                      // bugs caught on passing runs; a count, never reset
    public var furniture: [String] = []        // room pieces taken with stars (R4 §11)
    public var placed: [String] = []           // of those, the ones in the room right now
    public var guestbook: [GuestbookEntry] = []
    public var unlocked: [String] = []         // species ids, starter included
    public var owned: [String] = []            // Closet items
    public var worn: [String] = []
    public var ledger: [LedgerRow] = []
    public init() {}

    /// Stars are recomputed from the ledger every time, never stored as a trusted number.
    public var stars: Int { ledger.reduce(0) { $0 + $1.amount } }
    public var hatched: Bool { hatchedAt != nil }
}

public enum Stars {
    public static let perMeal = 1, firstCelebration = 5, perFiveApprovals = 1, focusSession = 2, reviewAnswered = 3, hatchingDay = 10

    /// Appends a row unless its ref is already in the ledger. Returns whether it was added.
    @discardableResult
    public static func earn(_ p: inout PetProgress, _ reason: String, _ amount: Int, ref: String, at: Date) -> Bool {
        guard amount != 0, !p.ledger.contains(where: { $0.ref == ref }) else { return false }
        p.ledger.append(LedgerRow(reason: reason, amount: amount, ref: ref, at: at))
        return true
    }

    /// A meal with a receipt: +1 star and one step of growth (once per receipt).
    public static func meal(_ p: inout PetProgress, receipt: String, at: Date) {
        guard !receipt.isEmpty, !p.meals.contains(receipt) else { return }
        p.meals.append(receipt)
        earn(&p, "meal", perMeal, ref: "meal-\(receipt)", at: at)
        p.stage = Stage.from(meals: p.meals.count, hatched: p.hatched, previous: p.stage)
    }

    public static func celebrated(_ p: inout PetProgress, at: Date) {
        p.celebrations += 1
        earn(&p, "first celebration", firstCelebration, ref: "first-celebration", at: at)
    }

    public static func approvalAnswered(_ p: inout PetProgress, at: Date) {
        p.approvalsAnswered += 1
        if p.approvalsAnswered % 5 == 0 { earn(&p, "5 approvals answered", perFiveApprovals, ref: "approvals-\(p.approvalsAnswered)", at: at) }
    }

    public static func focusFinished(_ p: inout PetProgress, id: String, at: Date) {
        p.focusSessions += 1
        earn(&p, "focus session", focusSession, ref: "focus-\(id)", at: at)
    }

    public static func reviewAnswered(_ p: inout PetProgress, id: String, at: Date) {
        p.reviewsAnswered += 1
        earn(&p, "teammate review answered", reviewAnswered, ref: "review-\(id)", at: at)
    }
}

// MARK: - The Closet (spec R3 §4)

public enum Closet {
    /// Star prices. Crown and wizard hat are milestone-only and have no price.
    public static let prices: [String: Int] = [
        "party": 5, "beanie": 10, "scarf": 10, "star": 12, "bow": 15, "cap": 15,
        "glasses": 20, "headphones": 20, "flower": 25, "shades": 25,
    ]
    public static let milestones: [String: String] = ["crown": "100 meals", "wizard": "reaching Elder"]

    public enum Availability: Equatable, Sendable { case owned, buy(stars: Int), needStars(have: Int, need: Int), milestone(String, progress: String) }

    public static func availability(_ item: String, _ p: PetProgress) -> Availability {
        if p.owned.contains(item) { return .owned }
        if let m = milestones[item] {
            let reached = item == "crown" ? p.meals.count >= 100 : p.stage == .elder
            if reached { return .buy(stars: 0) }
            return .milestone(m, progress: item == "crown" ? "\(p.meals.count) of 100 meals" : "\(p.stage)")
        }
        guard let price = prices[item] else { return .milestone("not available", progress: "") }
        return p.stars >= price ? .buy(stars: price) : .needStars(have: p.stars, need: price)
    }

    /// Takes the item for its stars (or for free once a milestone is reached). Stars only; nothing else.
    @discardableResult
    public static func take(_ item: String, _ p: inout PetProgress, at: Date) -> Bool {
        guard case let .buy(stars) = availability(item, p) else { return false }
        if stars > 0 { p.ledger.append(LedgerRow(reason: "closet: \(item)", amount: -stars, ref: "closet-\(item)", at: at)) }
        p.owned.append(item)
        return true
    }

    /// Wearing needs ownership; trying on (a preview) never does.
    public static func wear(_ item: String, _ p: inout PetProgress) -> Bool {
        guard p.owned.contains(item) else { return false }
        p.worn = Accessories.drawOrder(p.worn.filter { Slot.of($0) != Slot.of(item) } + [item])
        return true
    }
}

// MARK: - Hatching (spec R3 §3)

public struct Egg: Codable, Equatable, Sendable {
    public var calls = 0
    public var awaitingStop = false
    public var hatched = false
    public init() {}

    public enum Effect: Equatable, Sendable { case wobble(frame: Int), crack(frame: Int), glow, hatch }

    /// One tool call: wobble (frames 1/2 alternating), crack at 12 (3) and 25 (4), glow at 50 (5) then wait for Stop.
    public mutating func toolCall() -> Effect {
        guard !hatched else { return .wobble(frame: 7) }
        calls += 1
        if calls >= 50 { awaitingStop = true; return calls == 50 ? .glow : .crack(frame: 5) }
        if calls == 25 { return .crack(frame: 4) }
        if calls == 12 { return .crack(frame: 3) }
        return .wobble(frame: calls % 2 == 1 ? 1 : 2)
    }

    /// The Stop after the 50th call bursts it open (frames 6 then 7).
    public mutating func stop() -> Effect? {
        guard awaitingStop, !hatched else { return nil }
        hatched = true
        return .hatch
    }

    /// Option-click: hatch now, no penalty.
    public mutating func skip() -> Effect { hatched = true; awaitingStop = false; return .hatch }

    /// The hatch row frame the egg rests on between events.
    public var restFrame: Int { hatched ? 7 : calls >= 50 ? 5 : calls >= 25 ? 4 : calls >= 12 ? 3 : 0 }
}

// MARK: - Unlocks (spec D §2)

public enum Unlocks {
    /// Species newly earned by `p` (not yet in p.unlocked). Never from daily opens or streaks; never for sale.
    public static func earned(_ p: PetProgress, stompsForTako: Int = 50) -> [String] {
        var out: [String] = []
        if p.longestSession > 3600 { out.append("gremlo-gloop") }
        if p.toolCalls >= 1000 { out.append("gremlo-byte") }
        if p.failedRuns >= 1 { out.append("gremlo-puff") }
        if Set(p.thrivingDays).count >= 7 { out.append("gremlo-wisp") }
        if p.stomps >= stompsForTako { out.append("gremlo-tako") }
        return out.filter { !p.unlocked.contains($0) }
    }
}

// MARK: - One earner, many companions (spec D §2)

public enum Companions {
    /// The species for a companion on a new agent session: the next unlocked species that isn't the earner's and
    /// isn't already out, else the earner's own species. Companions hold no sign and earn nothing.
    public static func species(earner: String, unlocked: [String], inUse: [String]) -> String {
        let pool = unlocked.filter { $0 != earner }
        return pool.first { !inUse.contains($0) } ?? pool.first ?? earner
    }
}

// MARK: - Diary and certificate (spec D §8, R3 §3)

public struct DayCounts: Codable, Equatable, Sendable {
    public var runs = 0, failures = 0, approvals = 0
    public var tools: [String: Int] = [:]   // tool name -> count; never arguments, never paths
    public init() {}
}

public enum Diary {
    /// What the model is given for the day's entry: counts and outcomes only.
    public static func payload(_ d: DayCounts, species: String, voice: String, elder: Bool) -> [String: Any] {
        ["species": species, "voice": voice, "runs": d.runs, "failures": d.failures, "approvals": d.approvals,
         "tools": d.tools, "length": elder ? "longer" : "short"]
    }

    /// Word-wraps text into lines of at most `width` characters, for the share card.
    public static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = [], cur = ""
        for w in text.split(separator: " ") {
            if !cur.isEmpty && cur.count + 1 + w.count > width { lines.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : " ") + w
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    /// The entry when model text isn't allowed (or the network is down): a template over the same counts.
    public static func template(_ d: DayCounts, name: String) -> String {
        let top = d.tools.max { $0.value < $1.value }
        let toolLine = top.map { " Mostly \($0.key), \($0.value) times." } ?? ""
        let fail = d.failures == 0 ? "No stumbles." : "\(d.failures) stumble\(d.failures == 1 ? "" : "s")."
        return "\(name) watched \(d.runs) run\(d.runs == 1 ? "" : "s") today.\(toolLine) \(fail)"
    }
}

public struct Certificate: Equatable, Sendable {
    public let name: String, species: String, hatchedAt: Date, firstAgent: String
    public init(name: String, species: String, hatchedAt: Date, firstAgent: String) {
        self.name = name; self.species = species; self.hatchedAt = hatchedAt; self.firstAgent = firstAgent
    }
    /// The lines on the card. Never a repo, a path or a prompt.
    public func lines(dateFormat: (Date) -> String) -> [String] {
        ["\(name)", "a \(species)", "hatched \(dateFormat(hatchedAt))", "first agent: \(firstAgent)"]
    }
}
