import Foundation
import Testing
@testable import GremloCore

struct WingsTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func workingWhileARunIsOpen() {
        #expect(Wings.mode(working: true, endedAt: nil, failed: false, now: t0, quiet: false) == .working)
    }

    @Test func aFinishedRunGlowsForTheHoldThenGoesQuiet() {
        let end = t0
        #expect(Wings.mode(working: false, endedAt: end, failed: false, now: end.addingTimeInterval(0.5), quiet: false) == .done)
        #expect(Wings.mode(working: false, endedAt: end, failed: true, now: end.addingTimeInterval(0.5), quiet: false) == .failed)
        #expect(Wings.mode(working: false, endedAt: end, failed: false, now: end.addingTimeInterval(Wings.finishHold + 0.01), quiet: false) == .off)
    }

    @Test func nothingWithoutARun() {
        #expect(Wings.mode(working: false, endedAt: nil, failed: false, now: t0, quiet: false) == .off)
    }

    @Test func aShareMeetingOrFocusSilencesThem() {
        #expect(Wings.mode(working: true, endedAt: nil, failed: false, now: t0, quiet: true) == .off)
        #expect(Wings.mode(working: false, endedAt: t0, failed: false, now: t0, quiet: true) == .off)
    }

    @Test func aNewRunCancelsTheOldFinish() {
        // a prompt clears endedAt and sets working: the wings go straight back to working
        #expect(Wings.mode(working: true, endedAt: nil, failed: false, now: t0.addingTimeInterval(0.2), quiet: false) == .working)
    }
}
