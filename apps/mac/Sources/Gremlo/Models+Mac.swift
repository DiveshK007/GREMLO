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
    let thisDevicePaired: Bool? // this Mac's own key is paired (a reinstall makes a new one); nil from an older server
    let views: PetViews? // what the server holds for this pet; nil from an older server
    let purse: PurseInfo? // the pet's own purse, when it has one; it pays for each thought itself
}
/// Counted views wait `holdbackHours` (held), then queue for the worker (payable) until a settlement pays them.
struct PetViews: Decodable { let held: Int; let payable: Int; let holdbackHours: Double; let settledToday: Int; let settleError: String? }

/// Species are earned, never bought (spec D §2): starters are open; the rest show what unlocks them.
func speciesLock(_ id: String) -> String? { backend.growth.lockReason(id) }

struct ThinkResult: Decodable { let action: String; let say: String?; let reason: String?; let requestId: String?; let payFor: PayFor? }
/// A thought the pet's purse owes (server: bill); the Mac pays it with its pay_inference key.
struct PayFor: Codable, Equatable { let requestId: String; let amount: String; let payTo: String; let purse: String }
struct PurseInfo: Decodable, Equatable { let account: String; let perCall: String; let daily: String }

let popoverWidth: CGFloat = 340

// The product name, in one place, for every user-facing string in the Mac app.
let productName = "Gremlo"
let brokeReason = "sleeping: compute budget empty"

/// GREMLO_PET under the one pet-name rule. A bad name stops the app with a clear message rather than talking to
/// the server about a pet that can't exist (or quietly about someone else's).
func startupPetName() -> String {
    let raw = Legacy.env("PET")
    guard let n = PetName.startup(env: raw, saved: defaults.string(forKey: PetName.defaultsKey)) else {
        print("GREMLO_PET \"\(raw ?? "")\" isn't a pet name: use 2-24 of a-z, 0-9 and dashes, not starting or ending with a dash"); exit(1)
    }
    return n
}
