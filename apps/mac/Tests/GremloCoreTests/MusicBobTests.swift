import Foundation
import Testing
@testable import GremloCore

struct MusicBobTests {
    @Test func theOffsetStaysBetweenZeroAndTheLiftAndBouncesTwiceASecond() {
        let samples = stride(from: 0.0, to: 2.0, by: 0.01).map { MusicBob.offset(at: $0) }
        #expect(samples.min()! >= 0 && samples.max()! <= MusicBob.lift + 1e-9)
        #expect(samples.max()! > MusicBob.lift - 0.01, "it does reach the top")
        let tops = zip(samples, samples.dropFirst()).enumerated().filter { $0.offset > 0 && samples[$0.offset - 1] < $0.element.0 && $0.element.0 > $0.element.1 }.count
        #expect(tops == 4, "two seconds, two bounces a second")
    }

    @Test func itBobsOnlyWhenEveryConditionHolds() {
        let quiet = SilenceGate()
        func ok(playing: Bool = true, reduce: Bool = false, visible: Bool = true, floor: Bool = true, calm: Bool = true, gate: SilenceGate = quiet) -> Bool {
            MusicBob.allowed(playing: playing, reduceMotion: reduce, visible: visible, onFloor: floor, calm: calm, gate: gate)
        }
        #expect(ok())
        #expect(!ok(playing: false))
        #expect(!ok(reduce: true), "off under Reduce Motion")
        #expect(!ok(visible: false))
        #expect(!ok(floor: false), "not while climbing home")
        #expect(!ok(calm: false), "not mid-walk, mid-celebration or mid-fail")
        #expect(!ok(gate: SilenceGate(screenShared: true)))
        #expect(!ok(gate: SilenceGate(inMeeting: true)))
        #expect(!ok(gate: SilenceGate(fullScreenVideo: true)))
        #expect(ok(gate: SilenceGate(focus: true)), "Focus keeps it")
    }
}
