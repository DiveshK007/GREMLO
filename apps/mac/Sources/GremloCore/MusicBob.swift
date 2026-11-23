import Foundation

/// The pet's bob while music plays (Settings, Feel, Bops to music: opt-in). A steady 2 Hz, a couple of points up and
/// down, only while the pet stands about on the floor. No beat detection: it only knows that something is playing.
public enum MusicBob {
    public static let hz = 2.0
    public static let lift = 2.0   // points; the walk bounce is 3 and a celebration 6, so this stays the quietest

    /// Vertical offset in points at `time` seconds: 0 at rest, up to `lift`, `hz` bounces a second.
    public static func offset(at time: Double) -> Double { abs(sin(time * .pi * hz)) * lift }

    /// The pet bobs only when music is playing, motion is allowed, the pet is on screen, standing on the floor in a calm
    /// state, and nothing silences it (a screen share, a meeting or a full-screen video; Focus may keep it, since that is
    /// when people listen to music).
    public static func allowed(playing: Bool, reduceMotion: Bool, visible: Bool, onFloor: Bool, calm: Bool, gate: SilenceGate) -> Bool {
        playing && !reduceMotion && visible && onFloor && calm && !(gate.screenShared || gate.inMeeting || gate.fullScreenVideo)
    }
}
