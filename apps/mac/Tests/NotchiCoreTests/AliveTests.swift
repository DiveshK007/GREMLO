import CoreGraphics
import Foundation
import Testing
@testable import NotchiCore

let t0 = Date(timeIntervalSince1970: 1_794_500_000)

@Suite struct IdleSchedulerTests {
    @Test func firesEvery25to45SecondsWithSit3Yawn2() {
        var s = IdleScheduler(now: t0, seed: 42)
        var now = t0, counts: [Micro: Int] = [:], gaps: [Double] = []
        var last = t0
        for _ in 0..<4000 {
            now = s.nextAt
            if let m = s.next(now: now, quiet: Quiet()) { counts[m, default: 0] += 1 }
            gaps.append(s.nextAt.timeIntervalSince(now)); last = now
        }
        _ = last
        #expect(gaps.allSatisfy { $0 >= 25 && $0 <= 45 })
        let ratio = Double(counts[.sit] ?? 0) / Double(counts[.yawn] ?? 1)
        #expect(abs(ratio - 1.5) < 0.15, "sit:yawn should be 3:2, got \(ratio)")
    }

    @Test func nothingFiresEarlyOrUnderAnyQuietRule() {
        var s = IdleScheduler(now: t0, seed: 1)
        #expect(s.next(now: t0.addingTimeInterval(1), quiet: Quiet()) == nil, "not due yet")
        for q in [Quiet(holdingLine: true), Quiet(approvalWaiting: true), Quiet(inMeeting: true), Quiet(screenShared: true)] {
            var x = IdleScheduler(now: t0, seed: 1)
            #expect(x.next(now: x.nextAt, quiet: q) == nil)
            #expect(x.nextAt > t0.addingTimeInterval(25), "a skipped beat keeps the rhythm")
        }
    }

    @Test func theDaySeedRepeatsWithinADayAndChangesTomorrow() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let morning = Date(timeIntervalSince1970: 1_794_528_000)  // 2026-11-13 00:00 UTC
        #expect(SeededRNG.daySeed(morning, calendar: cal) == SeededRNG.daySeed(morning.addingTimeInterval(80_000), calendar: cal))
        #expect(SeededRNG.daySeed(morning, calendar: cal) != SeededRNG.daySeed(morning.addingTimeInterval(90_000), calendar: cal))
        var a = IdleScheduler(now: t0, seed: SeededRNG.daySeed(morning, calendar: cal)), b = IdleScheduler(now: t0, seed: SeededRNG.daySeed(morning, calendar: cal))
        #expect(a.nextAt == b.nextAt)
        #expect(a.next(now: a.nextAt, quiet: Quiet()) == b.next(now: b.nextAt, quiet: Quiet()))
    }

    @Test func napsAfter15MinutesOr5AtNight() {
        #expect(!IdleScheduler.shouldNap(idleFor: 14 * 60, night: false))
        #expect(IdleScheduler.shouldNap(idleFor: 15 * 60, night: false))
        #expect(IdleScheduler.shouldNap(idleFor: 5 * 60, night: true))
        #expect(!IdleScheduler.shouldNap(idleFor: 4 * 60, night: true))
    }
}

@Suite struct GazeTests {
    @Test func bandsAtTheSpecBoundaries() {
        #expect(Gaze.band(-151) == 0 && Gaze.band(-150) == 1 && Gaze.band(-41) == 1 && Gaze.band(-40) == 2)
        #expect(Gaze.band(0) == 2 && Gaze.band(40) == 2 && Gaze.band(41) == 3 && Gaze.band(150) == 3 && Gaze.band(151) == 4)
    }

    @Test func hysteresisHolds12PointsPastAnEdgeAndReachIs300() {
        var g = Gaze()
        #expect(g.update(offsetX: 0, distance: 10) == 2)
        #expect(g.update(offsetX: 45, distance: 50) == 2, "5 pt past the 40 edge: still centre")
        #expect(g.update(offsetX: 52, distance: 60) == 3, "12 pt past: moves")
        #expect(g.update(offsetX: 35, distance: 40) == 3, "back 5 pt inside centre: holds")
        #expect(g.update(offsetX: 28, distance: 30) == 2)
        #expect(g.update(offsetX: 0, distance: 301) == nil, "out of reach")
    }
}

@Suite struct PhysicsTests {
    func land(vy: CGFloat, vx: CGFloat = 0) -> Physics.Body {
        var b = Physics.Body(x: 100, y: 0.01, vx: vx, vy: -vy)
        for _ in 0..<5000 where !b.resting { Physics.step(&b, dt: 1.0 / 240, minX: 0, maxX: 1000) }
        return b
    }

    @Test func restitutionAndTheBounceCap() {
        var b = Physics.Body(x: 0, y: 0.01, vx: 0, vy: -1000)
        Physics.step(&b, dt: 0.001, minX: 0, maxX: 1000)
        #expect(abs(b.vy - 1002.4 * 0.35) < 1, "bounces back at 0.35 of the impact")
        let hard = land(vy: 2999)
        #expect(hard.resting && hard.bounces <= Physics.maxBounces + 1)
    }

    @Test func dizzyOnlyAboveTheThreshold() {
        #expect(land(vy: 1900).dizzy)
        #expect(!land(vy: 1700).dizzy)
    }

    @Test func releaseIsCappedAndFrictionSlowsOnContact() {
        let (vx, vy) = Physics.release(vx: 4000, vy: 3000)
        #expect(abs((vx * vx + vy * vy).squareRoot() - 3000) < 1e-6)
        #expect(abs(vx / vy - 4.0 / 3) < 1e-9, "direction kept")
        var b = Physics.Body(x: 500, y: 0.01, vx: 100, vy: -500)
        Physics.step(&b, dt: 0.001, minX: 0, maxX: 1000)
        #expect(abs(b.vx - 80) < 1e-9, "floor friction 0.8 on contact")
    }

    @Test func holdingLocksTheDoorPausesImpressionsAndReduceMotionNeverFlies() {
        #expect(Physics.rules(held: true) == .init(doorLocked: true, plateShown: false, countsImpressions: false))
        #expect(Physics.rules(held: false).countsImpressions)
        #expect(Physics.release(vx: 900, vy: 900, reduceMotion: true) == .fadeInPlace)
        if case .fly = Physics.release(vx: 900, vy: 900, reduceMotion: false) {} else { Issue.record("should fly") }
        #expect(!Physics.isGrab(pressedFor: 0.149) && Physics.isGrab(pressedFor: 0.15))
    }

    @Test func tenThrowsInAMinuteSulk() {
        let nine = (0..<9).map { t0.addingTimeInterval(Double($0)) }
        #expect(!Physics.sulks(throws: nine, now: t0.addingTimeInterval(10)))
        #expect(Physics.sulks(throws: nine + [t0.addingTimeInterval(20)], now: t0.addingTimeInterval(30)))
        #expect(!Physics.sulks(throws: nine + [t0.addingTimeInterval(20)], now: t0.addingTimeInterval(65)), "older than a minute")
    }
}

@Suite struct SocialTests {
    typealias P = (id: String, x: CGFloat, dir: CGFloat, free: Bool, visitor: Bool)

    @Test func meetsOnlyWhenCloseFreeAndFacingEachOther() {
        var s = Social(), rng = SeededRNG(seed: 7)
        let a: P = ("a", 100, 1, true, false), b: P = ("b", 150, -1, true, false)
        #expect(s.meet(a, ("b", 170, -1, true, false), now: t0, quiet: Quiet(), rng: &rng) == nil, "70 pt apart")
        #expect(s.meet(a, ("b", 150, 1, true, false), now: t0, quiet: Quiet(), rng: &rng) == nil, "walking the same way")
        #expect(s.meet(a, ("b", 150, -1, false, false), now: t0, quiet: Quiet(), rng: &rng) == nil, "the earner holding a line isn't free")
        #expect(s.meet(a, b, now: t0, quiet: Quiet(holdingLine: true), rng: &rng) == nil, "quiet rules")
        #expect(s.meet(a, b, now: t0, quiet: Quiet(), rng: &rng)?.first == .wave)
        #expect(s.meet(a, b, now: t0.addingTimeInterval(599), quiet: Quiet(), rng: &rng) == nil, "10 min pair cooldown")
        #expect(s.meet(a, b, now: t0.addingTimeInterval(600), quiet: Quiet(), rng: &rng) != nil)
    }

    @Test func rollRatesAndTheHourlyCapAndVisitorsOnlyWave() {
        var rng = SeededRNG(seed: 99)
        var hi = 0, chase = 0
        for i in 0..<10_000 {
            var s = Social()
            let r = s.meet(("a\(i)", 0, 1, true, false), ("b\(i)", 30, -1, true, false), now: t0, quiet: Quiet(), rng: &rng)!
            if r.contains(.highFive) { hi += 1 }
            if r.contains(.chase) { chase += 1 }
        }
        #expect(abs(Double(hi) / 10_000 - 0.35) < 0.02)
        #expect(abs(Double(chase) / 10_000 - 0.15) < 0.02)
        var s = Social()
        for i in 0..<6 { #expect(s.meet(("x\(i)", 0, 1, true, false), ("y\(i)", 30, -1, true, false), now: t0.addingTimeInterval(Double(i)), quiet: Quiet(), rng: &rng) != nil) }
        #expect(s.meet(("x9", 0, 1, true, false), ("y9", 30, -1, true, false), now: t0.addingTimeInterval(10), quiet: Quiet(), rng: &rng) == nil, "6 an hour")
        var v = Social()
        #expect(v.meet(("me", 0, 1, true, false), ("visitor", 30, -1, true, true), now: t0, quiet: Quiet(), rng: &rng) == [.wave])
    }
}

@Suite struct ContextTests {
    @Test func nightBatteryAndFirstSession() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Date(timeIntervalSince1970: 1_794_528_000) // 00:00 UTC
        #expect(Context.isNight(day, calendar: cal))
        #expect(Context.isNight(day.addingTimeInterval(5 * 3600 + 3599), calendar: cal))
        #expect(!Context.isNight(day.addingTimeInterval(6 * 3600), calendar: cal))
        #expect(Context.isNight(day.addingTimeInterval(23 * 3600), calendar: cal))
        #expect(Context.power(percent: 19, onBattery: true) == .low && Context.frameRateFactor(.low) == 0.5)
        #expect(Context.power(percent: 9, onBattery: true) == .critical)
        #expect(Context.power(percent: 5, onBattery: false) == .normal, "plugged in")
        #expect(Context.power(percent: nil, onBattery: true) == .normal, "no battery reading: no change")
        #expect(Context.firstSessionToday(lastSignature: nil, now: day, calendar: cal))
        #expect(!Context.firstSessionToday(lastSignature: day.addingTimeInterval(60), now: day.addingTimeInterval(7200), calendar: cal))
        #expect(Context.firstSessionToday(lastSignature: day, now: day.addingTimeInterval(86_400), calendar: cal))
    }
}

@Suite struct ToolPropTests {
    @Test func propTableFromTheSpec() {
        let cases: [(String, String?, Prop?)] = [
            ("Edit", nil, .wrench), ("Write", nil, .wrench), ("MultiEdit", nil, .wrench), ("apply_patch", nil, .wrench), ("edit_file", nil, .wrench),
            ("Read", nil, .magnifier), ("Grep", nil, .magnifier), ("Glob", nil, .magnifier), ("read_file", nil, .magnifier), ("grep_search", nil, .magnifier),
            ("Bash", "pytest -q", .flask), ("shell", "cargo test", .flask), ("run_terminal_cmd", "npm test", .flask),
            ("Bash", "ls -la", .terminal), ("shell", "git status", .terminal), ("run_terminal_cmd", nil, .terminal),
            ("WebFetch", nil, .globe), ("WebSearch", nil, .globe), ("web_search", nil, .globe),
            ("TodoWrite", nil, .notepad), ("update_plan", nil, .notepad), ("todo_write", nil, .notepad),
            ("SomeNewTool", nil, nil), ("mcp__x__y", nil, nil),
        ]
        for (tool, cmd, want) in cases { #expect(Tools.prop(tool: tool, command: cmd) == want, "\(tool) \(cmd ?? "")") }
    }

    @Test func runnerMatcherTable() {
        let yes = ["npm test", "pnpm test", "yarn test", "bun test", "npm run test -- --watch=false", "vitest run", "npx vitest", "jest --ci",
                   "pytest tests/", "python -m pytest", "go test ./...", "cargo test -p x", "forge test -vv", "mix test", "rspec spec/a_spec.rb",
                   "bundle exec rspec", "dotnet test", "swift test", "mocha", "CI=1 npm test", "cd apps/server && npm test"]
        let no = ["npm install", "npm run build", "go build ./...", "cargo build", "echo test", "git commit -m 'test'", "ls test/", "swift build"]
        for c in yes { #expect(Tools.runner(c) != nil, "\(c) is a test run") }
        for c in no { #expect(Tools.runner(c) == nil, "\(c) is not a test run") }
        #expect(Tools.runner("make check", extra: [#"^make\s+check\b"#]) != nil, "user patterns")
    }
}
