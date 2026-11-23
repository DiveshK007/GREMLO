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

    @Test func fastTimingShrinksTheBreakAndKeepsTheShape() {
        var p = Pomodoro(fast: true)
        #expect(p.focusEnded(at: t0) == .startBreak)
        #expect(p.breakRemaining(t0) == 5)
        #expect(p.breakLabel == "5 seconds")
        #expect(p.left(3.2) == "4 s")
        #expect(Pomodoro().left(299) == "5 min")
        #expect(p.breakFinished(t0.addingTimeInterval(5)))
    }

    @Test func aFocusSessionCanBeShorterThanItsMinutesOnlyWhenToldTo() {
        let s = FocusSession(start: t0, minutes: 25)
        #expect(s.length == 1500 && s.end == t0.addingTimeInterval(1500))
        let f = FocusSession(start: t0, minutes: 25, seconds: 25)
        #expect(f.end == t0.addingTimeInterval(25) && f.progress(t0.addingTimeInterval(5)) == 0.2)
    }

    @Test func aBreakCountsDown() {
        var p = Pomodoro()
        _ = p.focusEnded(at: t0)
        #expect(!p.breakFinished(t0.addingTimeInterval(299)))
        #expect(p.breakRemaining(t0.addingTimeInterval(240)) == 60)
        #expect(p.breakRemaining(t0.addingTimeInterval(900)) == 0)
    }
}
