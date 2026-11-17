import Foundation

/// Time the agent worked while you waited today (prompt to stop), counted on this Mac from hook events, never uploaded.
public struct WaitClock {
    public var day = "", seconds = 0.0, since: Date?
    public init() {}
    public static let maxStretch = 3600.0 // a lost Stop (crash, kill) must not count the whole night
    public static func dayOf(_ d: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: d); return "\(c.year!)-\(c.month!)-\(c.day!)" }
    public mutating func handle(_ event: String, at now: Date = Date()) {
        if WaitClock.dayOf(now) != day { day = WaitClock.dayOf(now); seconds = 0 }
        switch event {
        case "UserPromptSubmit": close(now); since = now
        case "Stop", "StopFailure", "SessionEnd": close(now)
        default: break
        }
    }
    public mutating func close(_ now: Date) {
        if let s = since { seconds += min(max(now.timeIntervalSince(s), 0), WaitClock.maxStretch) }
        since = nil
    }
    public func minutes(at now: Date = Date()) -> Int {
        guard WaitClock.dayOf(now) == day else { return 0 }
        return Int((seconds + (since.map { min(now.timeIntervalSince($0), WaitClock.maxStretch) } ?? 0)) / 60)
    }
}
