import GremloCore
import AppKit
import CryptoKit
import Network
import UserNotifications

// What the server sends, the wait clock and the money formatting (moved out of main.swift unchanged).

struct Campaign: Decodable {
    let campaignId: String; let line: String?; let hooks: [String]?; let url: String?; let order: [Int]?; let brand: String; let ratePerImpression: String
    let paused: [Int]?; let moments: [String]? // lines paused by reports; a moment tag per line (R2 §15)
    var allHooks: [String] { hooks?.isEmpty == false ? hooks! : line.map { [$0] } ?? [] }
}
struct Thought: Decodable { let action: String; let requestId: String; let at: Int; let model: String?; let chargeTx: String? }
struct PetInfo: Decodable {
    let name: String; let mood: String; let moodReason: String?; let walletBalance: String?; let computeBalance: String?
    let impressionsToday: Int; let lastThoughts: [Thought]; let seeded: Bool
    let paidViews: Int?; let earnedWei: String?; let level: Int?; let streak: Int? // nil: older server or chain unreadable
    let explorer: String? // nearblocks for the server's network
    let meals: [String]? // settlement txs that fed the compute budget: one meal each, for growth
    let paired: Bool? // a Mac is paired to this pet; nil from an older server
    let purse: PurseInfo? // the pet's own purse, when it has one; it pays for each thought itself
}

/// Species are earned, never bought (spec D §2): starters are open; the rest show what unlocks them.
func speciesLock(_ id: String) -> String? { backend.growth.lockReason(id) }

/// Time the agent worked while you waited today (prompt to stop), counted on this Mac from hook events, never uploaded.
struct WaitClock {
    var day = "", seconds = 0.0, since: Date?
    static let maxStretch = 3600.0 // a lost Stop (crash, kill) must not count the whole night
    static func dayOf(_ d: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: d); return "\(c.year!)-\(c.month!)-\(c.day!)" }
    mutating func handle(_ event: String, at now: Date = Date()) {
        if WaitClock.dayOf(now) != day { day = WaitClock.dayOf(now); seconds = 0 }
        switch event {
        case "UserPromptSubmit": close(now); since = now
        case "Stop", "StopFailure", "SessionEnd": close(now)
        default: break
        }
    }
    mutating func close(_ now: Date) {
        if let s = since { seconds += min(max(now.timeIntervalSince(s), 0), WaitClock.maxStretch) }
        since = nil
    }
    func minutes(at now: Date = Date()) -> Int {
        guard WaitClock.dayOf(now) == day else { return 0 }
        return Int((seconds + (since.map { min(now.timeIntervalSince($0), WaitClock.maxStretch) } ?? 0)) / 60)
    }
}
struct ThinkResult: Decodable { let action: String; let say: String?; let reason: String?; let requestId: String?; let payFor: PayFor? }
/// A thought the pet's purse owes (server: bill); the Mac pays it with its pay_inference key.
struct PayFor: Codable, Equatable { let requestId: String; let amount: String; let payTo: String; let purse: String }
struct PurseInfo: Decodable, Equatable { let account: String; let perCall: String; let daily: String }

let popoverWidth: CGFloat = 340

/// Whether the pet keeps out of sight. Ads never depend on mood: a hungry pet (compute budget empty) still walks the
/// sponsored sign while the agent works, because that's how it earns food. Mood only stops the paid AI calls.
/// Only an asleep pet (the chain can't be read) with no agent work stays home.
func staysHome(mood: String, agentWorking: Bool) -> Bool { mood == "asleep" && !agentWorking }
// The product name, in one place, for every user-facing string in the Mac app.
let productName = "Gremlo"
let brokeReason = "sleeping: compute budget empty"

// yoctoNEAR string to "0.0192 NEAR": 4 decimals, rounded down so the popover never shows more than the account holds.
func near4(_ yocto: String?) -> String {
    guard let yocto, !yocto.isEmpty, yocto.allSatisfy({ $0.isASCII && $0.isNumber }), var units = Decimal(string: yocto) else { return "\u{2014}" }
    units /= Decimal(sign: .plus, exponent: 20, significand: 1)
    var whole = Decimal()
    NSDecimalRound(&whole, &units, 0, .down)
    let digits = String(repeating: "0", count: max(0, 5 - "\(whole)".count)) + "\(whole)"
    return "\(digits.dropLast(4)).\(digits.suffix(4))"  // product copy names no chain; the unit lives in Advanced and the docs
}

func nearAmount(_ yocto: Decimal) -> String { "\(yocto / Decimal(sign: .plus, exponent: 24, significand: 1))" }

// "+0.0002 NEAR" when the balance went up, nil otherwise (first poll, unknown, same or down).
func nearGain(_ old: String?, _ new: String?) -> String? {
    guard let o = old.flatMap({ Decimal(string: $0) }), let n = new.flatMap({ Decimal(string: $0) }), n > o else { return nil }
    return "+" + nearAmount(n - o)
}

/// GREMLO_PET under the one pet-name rule. A bad name stops the app with a clear message rather than talking to
/// the server about a pet that can't exist (or quietly about someone else's).
func startupPetName() -> String {
    let raw = Legacy.env("PET") ?? "mochi"
    guard let n = PetName.clean(raw) else { print("GREMLO_PET \"\(raw)\" isn't a pet name: use 2-24 of a-z, 0-9 and dashes, not starting or ending with a dash"); exit(1) }
    return n
}
