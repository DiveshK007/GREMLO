import Foundation

/// What the progress wings beside the notch show. There is no percentage here on purpose: an agent run has no known
/// length, so the wings say "working", "done" or "failed" and never a made-up fraction.
public enum WingsMode: Equatable, Sendable { case off, working, done, failed }

public enum Wings {
    /// How long the finish (the glow, or the red fill) stays after the run ends, in seconds.
    public static let finishHold = 1.4
    /// Wider than this and the housing is a card; the wings would run off the panel, so they step aside.
    public static let maxHousingWidth = 640.0

    /// `working`: a run has started and not ended. `quiet`: a screen share, a meeting or Focus (the pet stays calm then).
    public static func mode(working: Bool, endedAt: Date?, failed: Bool, now: Date, quiet: Bool) -> WingsMode {
        if quiet { return .off }
        if working { return .working }
        if let end = endedAt, now.timeIntervalSince(end) < finishHold { return failed ? .failed : .done }
        return .off
    }
}
