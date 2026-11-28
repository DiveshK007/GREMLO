// The panel's Health rows: why nothing is happening, in plain words. Pure, so the order of the reasons is tested.

public enum Health {
    /// Everything that decides whether this Mac's views count right now.
    public struct Gate {
        public var server: LocalLife.Why?   // nil: the server answered and knows the pet
        public var thisMacPaired: Bool?     // nil: not known yet
        public var secureEnclave = true
        public var egg = false, demo = false, paused = false, focus = false, stream = false
        public var sponsored = true, quietHours = false, capped = false, silenced = false
        public var campaign = true
        public init(server: LocalLife.Why?, thisMacPaired: Bool?) { self.server = server; self.thisMacPaired = thisMacPaired }
    }

    /// The first thing stopping views from counting, in the order to fix them; nil when they count.
    public static func blocker(_ g: Gate) -> String? {
        switch g.server {
        case .unregistered: return "the pet isn't registered yet"
        case .serverDown: return "the server can't be reached"
        case .offline: return "this Mac is offline"
        case nil: break
        }
        if !g.secureEnclave { return "this Mac has no Secure Enclave to sign views" }
        if g.thisMacPaired == false { return "this Mac isn't paired" }
        if g.egg { return "still an egg: it hatches after 50 tool calls" }
        if g.demo { return "demo mode is on" }
        if g.paused { return "paused" }
        if g.focus { return "focus is on" }
        if g.stream { return "stream mode is on (it stays on after a restart)" }
        if !g.sponsored { return "sponsored lines are off (Settings, Earning)" }
        if g.quietHours { return "quiet hours, until 08:00" }
        if g.capped { return "the daily limit is reached" }
        if !g.campaign { return "no campaign is running" }
        if g.silenced { return "hidden during a screen share, meeting or full-screen video" }
        return nil
    }

    /// "12 today · 8 on hold 24 h · 4 to pay · 3 paid today"; zero parts are left out, so a quiet day reads "0 today".
    public static func views(today: Int, held: Int?, payable: Int?, settledToday: Int?, holdbackHours: Double?) -> String {
        var parts = ["\(today) today"]
        if let held, held > 0 { parts.append("\(held) on hold" + (holdbackHours.map { $0 > 0 ? " \(Int($0)) h" : "" } ?? "")) }
        if let payable, payable > 0 { parts.append("\(payable) to pay") }
        if let settledToday, settledToday > 0 { parts.append("\(settledToday) paid today") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// What the menu bar icon says at a glance, and the same words for VoiceOver. Approval first: it is the one that waits on you.
public enum MenuBarState: Equatable, Sendable {
    case normal, approval, away(String), quiet(String)

    public static func of(approvalWaiting: Bool, server: LocalLife.Why?, paused: Bool, focus: Bool) -> MenuBarState {
        if approvalWaiting { return .approval }
        switch server {
        case .offline: return .away("offline")
        case .serverDown: return .away("can't reach the server")
        case .unregistered: return .away("pet not registered")
        case nil: break
        }
        if paused { return .quiet("paused") }
        if focus { return .quiet("focus") }
        return .normal
    }

    public func label(_ product: String) -> String {
        switch self {
        case .normal: return product
        case .approval: return "\(product): needs your approval"
        case .away(let why), .quiet(let why): return "\(product): \(why)"
        }
    }
}
