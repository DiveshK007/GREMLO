import Foundation

/// A Pomodoro run on top of a Focus session: 25 minutes of focus, 5 of break, four times. The focus blocks are the
/// existing Focus sessions (same pet focus state, sound and 2 stars each); this only decides what follows a block.
/// It is off by default and starts only from a 25-minute focus. Ending early (End, the hotkey, a new session) stops
/// the whole run.
public struct Pomodoro: Equatable, Sendable {
    public static let focusMinutes = 25, breakMinutes = 5, cycles = 4

    public enum Next: Equatable, Sendable { case startBreak, startFocus(cycle: Int), finished }

    public private(set) var cycle = 1
    public private(set) var breakEnd: Date?
    public var onBreak: Bool { breakEnd != nil }
    public init() {}

    /// A run starts only when the setting is on and the session is the 25-minute one.
    public static func startsRun(minutes: Int, enabled: Bool) -> Bool { enabled && minutes == focusMinutes }

    /// A focus block finished (not ended early): a break follows, unless that was the last block.
    public mutating func focusEnded(at now: Date) -> Next {
        guard cycle < Self.cycles else { return .finished }
        breakEnd = now.addingTimeInterval(Double(Self.breakMinutes) * 60)
        return .startBreak
    }

    /// The break is over: the next block starts.
    public mutating func breakEnded() -> Next {
        breakEnd = nil
        cycle += 1
        return .startFocus(cycle: cycle)
    }

    public func breakFinished(_ now: Date) -> Bool { breakEnd.map { now >= $0 } ?? false }
    public func breakRemaining(_ now: Date) -> TimeInterval { max(0, breakEnd?.timeIntervalSince(now) ?? 0) }
}
