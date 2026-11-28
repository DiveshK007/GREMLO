import Foundation
import Testing
@testable import GremloCore

// Moved here from asserts at the top of main.swift, so they run under `swift test` and not at every launch.
@Suite struct MoneyWaitTests {
    @Test func nearGainShowsOnlyIncreases() {
        #expect(nearGain("1000000000000000000000000", "1000200000000000000000000") == "+0.0002")
        #expect(nearGain("123456789012345678901234567", "123456789012345678901234568") == "+0.000000000000000000000001")
        #expect(nearGain("5", "5") == nil && nearGain("5", "4") == nil && nearGain(nil, "5") == nil)
    }

    @Test func near4RoundsDownAndRefusesJunk() {
        #expect(near4("19279999998320000000000") == "0.0192" && near4("0") == "0.0000" && near4("1000000000000000000000000000") == "1000.0000")
        #expect(near4("99999999999999999999") == "0.0000" && near4(nil) == "\u{2014}")
        #expect(near4("-5") == "\u{2014}" && near4("0x1f") == "\u{2014}" && near4(" 5") == "\u{2014}" && near4("") == "\u{2014}")
    }

    @Test func onlyAnIdleAsleepPetStaysHome() {
        #expect(!staysHome(mood: "hungry", agentWorking: true) && !staysHome(mood: "hungry", agentWorking: false), "a hungry pet still shows the sign")
        #expect(!staysHome(mood: "asleep", agentWorking: true) && staysHome(mood: "asleep", agentWorking: false))
        #expect(!staysHome(mood: "thriving", agentWorking: true) && !staysHome(mood: "stable", agentWorking: false))
        #expect(!staysHome(mood: LocalLife.mood, agentWorking: false), "a pet the server can't vouch for still lives on the floor")
    }

    @Test func waitClockCountsPromptToStopAndCapsALostStop() {
        var w = WaitClock()
        let t0 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! // away from midnight
        w.handle("UserPromptSubmit", at: t0); w.handle("PreToolUse", at: t0 + 60); w.handle("Stop", at: t0 + 120)
        #expect(w.minutes(at: t0 + 130) == 2)
        w.handle("UserPromptSubmit", at: t0 + 200); w.handle("UserPromptSubmit", at: t0 + 200 + 7200)
        #expect(w.minutes(at: t0 + 200 + 7200) == 62)
    }

    @Test func serverErrorTextIsTheServersOwnWords() {
        #expect(ServerError.text(#"HTTP 400 {"error":"view not counted: the screen was locked"}"#) == "view not counted: the screen was locked")
        #expect(ServerError.text(#"HTTP 401 {"error":"pair this Mac with your pet first (Gremlo menu \"Settings\")"}"#) == #"pair this Mac with your pet first (Gremlo menu "Settings")"#)
        #expect(ServerError.text("The request timed out.") == "The request timed out.", "a network failure stays as it is")
        #expect(ServerError.text(#"HTTP 502 {"error":"cut sho"#) == #"HTTP 502 {"error":"cut sho"#, "a cut-off body is shown raw, not guessed at")
    }
}
