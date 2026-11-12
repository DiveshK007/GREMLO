import Foundation
import Testing
@testable import NotchiCore

@Suite struct GrowthTests {
    let t = Date(timeIntervalSince1970: 1000)

    @Test func stagesComeFromMealsAndNeverGoBack() {
        #expect(Stage.from(meals: 99, hatched: false) == .egg)
        #expect(Stage.from(meals: 0, hatched: true) == .hatchling && Stage.from(meals: 9, hatched: true) == .hatchling)
        #expect(Stage.from(meals: 10, hatched: true) == .buddy && Stage.from(meals: 49, hatched: true) == .buddy)
        #expect(Stage.from(meals: 50, hatched: true) == .elder)
        #expect(Stage.from(meals: 3, hatched: true, previous: .elder) == .elder, "never backwards")
    }

    @Test func aMealCountsOncePerReceipt() {
        var p = PetProgress(); p.hatchedAt = t
        for i in 0..<10 { Stars.meal(&p, receipt: "tx\(i)", at: t) }
        Stars.meal(&p, receipt: "tx3", at: t)
        Stars.meal(&p, receipt: "", at: t)
        #expect(p.meals.count == 10 && p.stars == 10 && p.stage == .buddy)
    }

    @Test func starsAreEarnedOnlyAndTheClosetSpendsThem() {
        var p = PetProgress(); p.hatchedAt = t
        Stars.earn(&p, "hatching day", Stars.hatchingDay, ref: "hatch", at: t)
        Stars.celebrated(&p, at: t); Stars.celebrated(&p, at: t)
        for _ in 0..<10 { Stars.approvalAnswered(&p, at: t) }
        Stars.focusFinished(&p, id: "f1", at: t); Stars.focusFinished(&p, id: "f1", at: t)
        Stars.reviewAnswered(&p, id: "r1", at: t)
        #expect(p.stars == 10 + 5 + 2 + 2 + 3, "first celebration once, a ref counts once")
        #expect(Closet.availability("glasses", p) == .buy(stars: 20))
        #expect(Closet.take("glasses", &p, at: t) && p.stars == 2)
        #expect(Closet.availability("glasses", p) == .owned)
        #expect(Closet.availability("shades", p) == .needStars(have: 2, need: 25))
        #expect(!Closet.take("shades", &p, at: t) && p.stars == 2)
        #expect(Closet.availability("crown", p) == .milestone("100 meals", progress: "0 of 100 meals"))
        #expect(!Closet.take("crown", &p, at: t))
        p.stage = .elder
        #expect(Closet.take("wizard", &p, at: t) && p.stars == 2, "milestone items cost nothing")
        #expect(Closet.wear("glasses", &p) && Closet.wear("wizard", &p) && !Closet.wear("shades", &p))
        #expect(Closet.wear("glasses", &p) && p.worn.count == 2, "one item per slot")
    }

    @Test func noMoneyPathExistsInGrowth() throws {
        // Stars can't be bought, gifted or sold, and no money is ever shown (R3 §4). This fails if a money word or a
        // currency amount ever appears in the growth code.
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/NotchiCore/Growth.swift").standardized, encoding: .utf8)
        let banned = #"(?i)(\$(\s|\d+\.\d)|\b(usd|cents?|yocto|near|wallet|checkout|storekit|iap|invoice|payment|buy(Stars|With)|gift|sell)\b)"#
        let hits = src.components(separatedBy: "\n").filter { $0.range(of: banned, options: .regularExpression) != nil }
        #expect(hits.isEmpty, "\(hits)")
        #expect(Set(Closet.prices.keys).isDisjoint(with: Closet.milestones.keys))
        #expect(Closet.prices.count + Closet.milestones.count == 12, "all twelve accessories accounted for")
    }

    @Test func hatchingFollowsTheCrackTable() {
        var e = Egg()
        var fx: [Egg.Effect] = []
        for _ in 0..<50 { fx.append(e.toolCall()) }
        #expect(fx[0] == .wobble(frame: 1) && fx[1] == .wobble(frame: 2))
        #expect(fx[11] == .crack(frame: 3) && fx[24] == .crack(frame: 4) && fx[49] == .glow)
        #expect(e.restFrame == 5 && !e.hatched)
        #expect(e.stop() == .hatch && e.hatched && e.restFrame == 7)
        #expect(e.stop() == nil, "hatches once")
        var early = Egg(); _ = early.toolCall()
        #expect(early.stop() == nil, "a Stop before the 50th call does nothing")
        #expect(early.skip() == .hatch && early.hatched, "option-click skips with no penalty")
    }

    @Test func unlocksAndCompanions() {
        var p = PetProgress(); p.unlocked = ["notchi"]
        #expect(Unlocks.earned(p).isEmpty)
        p.longestSession = 3700; p.toolCalls = 1000; p.failedRuns = 1; p.stomps = 50
        p.thrivingDays = ["d1", "d2", "d3", "d4", "d5", "d6", "d6"]
        #expect(Unlocks.earned(p) == ["notchi-gloop", "notchi-byte", "notchi-puff", "notchi-tako"], "6 distinct thriving days is not 7")
        p.thrivingDays.append("d7"); p.unlocked.append("notchi-byte")
        #expect(Unlocks.earned(p) == ["notchi-gloop", "notchi-puff", "notchi-wisp", "notchi-tako"])
        #expect(Companions.species(earner: "notchi", unlocked: ["notchi", "notchi-pip", "notchi-moss"], inUse: ["notchi-pip"]) == "notchi-moss")
        #expect(Companions.species(earner: "notchi", unlocked: ["notchi"], inUse: []) == "notchi")
    }

    @Test func diaryAndCertificateCarryNoCodeOrPaths() {
        var d = DayCounts(); d.runs = 3; d.failures = 1; d.tools = ["Edit": 12, "Bash": 4]
        #expect(Diary.template(d, name: "Mochi") == "Mochi watched 3 runs today. Mostly Edit, 12 times. 1 stumble.")
        let payload = Diary.payload(d, species: "bean", voice: "plain", elder: false)
        #expect(Set(payload.keys) == ["species", "voice", "runs", "failures", "approvals", "tools", "length"])
        let c = Certificate(name: "Mochi", species: "bean", hatchedAt: t, firstAgent: "Claude Code")
        #expect(c.lines { _ in "1 Jan" } == ["Mochi", "a bean", "hatched 1 Jan", "first agent: Claude Code"])
    }
}
