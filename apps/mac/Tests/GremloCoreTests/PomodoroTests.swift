import Foundation
import Testing
@testable import GremloCore

struct PomodoroTests {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    @Test func onlyTheSettingPlusA25MinuteSessionStartsARun() {
        #expect(Pomodoro.startsRun(minutes: 25, enabled: true))
        #expect(!Pomodoro.startsRun(minutes: 25, enabled: false))
        #expect(!Pomodoro.startsRun(minutes: 50, enabled: true))
        #expect(!Pomodoro.startsRun(minutes: 90, enabled: true))
    }

    @Test func fourBlocksWithABreakBetweenEach() {
        var p = Pomodoro()
        var now = t0
        for block in 1...3 {
            #expect(p.cycle == block && !p.onBreak)
            #expect(p.focusEnded(at: now) == .startBreak)
            #expect(p.onBreak)
            #expect(p.breakRemaining(now) == 300, "a 5-minute break")
            now = now.addingTimeInterval(300)
            #expect(p.breakFinished(now))
            #expect(p.breakEnded() == .startFocus(cycle: block + 1))
        }
        #expect(p.cycle == 4)
        #expect(p.focusEnded(at: now) == .finished, "no break after the last block")
        #expect(!p.onBreak)
    }

    @Test func aBreakCountsDown() {
        var p = Pomodoro()
        _ = p.focusEnded(at: t0)
        #expect(!p.breakFinished(t0.addingTimeInterval(299)))
        #expect(p.breakRemaining(t0.addingTimeInterval(240)) == 60)
        #expect(p.breakRemaining(t0.addingTimeInterval(900)) == 0)
    }
}
