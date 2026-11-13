import CoreGraphics
import Foundation
import Testing
@testable import GremloCore

@Suite struct RoomTests {
    let t = Date(timeIntervalSince1970: 100_000)

    @Test func furnitureSpendsTheSameStarsAndPutsAway() {
        var p = PetProgress()
        Stars.earn(&p, "hatching day", 10, ref: "hatch", at: t)
        Stars.celebrated(&p, at: t)
        #expect(Room.take("rug", &p, at: t) && p.stars == 7 && p.placed == ["rug"])
        #expect(!Room.take("rug", &p, at: t), "once")
        #expect(!Room.take("fishbowl", &p, at: t), "15 stars needed")
        Room.toggle("rug", &p)
        #expect(p.placed.isEmpty && p.furniture == ["rug"], "put away, still yours")
        Room.toggle("rug", &p)
        #expect(Room.petSpot(placed: p.placed, night: false, agentWorking: false).item?.id == "rug")
        #expect(Room.petSpot(placed: ["rug", "beanbag"], night: true, agentWorking: false).row == .night)
        #expect(Room.petSpot(placed: ["radio"], night: false, agentWorking: true).row == .celebrate)
        #expect(Room.items.count == 9 && Room.items.allSatisfy { $0.x < Room.size.w && $0.y < Room.size.h })
    }

    @Test func guestbookKeepsOnlyTheFiveFields() throws {
        let v: [String: Any] = ["name": "Bean", "species": "gremlo-pip", "stage": "buddy", "outfit": ["beanie", "rolex"], "message": "hi", "owner": "alice"]
        let e = try #require(GuestbookEntry.from(v, at: t))
        #expect(e.pet == "Bean" && e.species == "gremlo-pip" && e.stage == "buddy" && e.outfit == ["beanie"])
        let keys = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any]).keys
        #expect(Set(keys) == ["pet", "species", "stage", "outfit", "at"], "no messages, no owner names")
        #expect(GuestbookEntry.from(["name": "x", "species": "dragon"], at: t) == nil)
    }

    @Test func focusDuckAndLines() {
        let f = FocusSession(start: t, minutes: 25)
        #expect(f.label(t.addingTimeInterval(60)) == "24:00" && !f.finished(t.addingTimeInterval(1499)) && f.finished(t.addingTimeInterval(1500)))
        #expect(abs(f.progress(t.addingTimeInterval(750)) - 0.5) < 0.001)
        #expect(Duck.decide(screenShared: true, inMeeting: true, focus: true, fullScreen: true, streamMode: false) == .intoNotch)
        #expect(Duck.decide(screenShared: true, inMeeting: false, focus: false, fullScreen: false, streamMode: true) == Duck.none, "stream mode suspends the share rule")
        #expect(Duck.decide(screenShared: false, inMeeting: true, focus: true, fullScreen: false, streamMode: false) == .sleep)
        #expect(Duck.decide(screenShared: false, inMeeting: false, focus: true, fullScreen: false, streamMode: false) == .home)
        var l = LineLimiter()
        #expect(l.allows(brand: "A", now: t)); l.record(brand: "A", now: t)
        #expect(!l.allows(brand: "A", now: t.addingTimeInterval(60)), "never the same brand twice in a row")
        for i in 1..<12 { l.record(brand: i % 2 == 0 ? "A" : "B", now: t.addingTimeInterval(Double(i))) }
        #expect(!l.allows(brand: "C", now: t.addingTimeInterval(100)), "12 an hour")
        #expect(l.allows(brand: "C", now: t.addingTimeInterval(3601)))
    }

    @Test func streamModeHasNoPlateAndNoCommand() {
        let p = StreamOverlay.payload(name: "Mochi", species: "gremlo", stage: .buddy, mood: "thriving", tools: 12, waiting: true)
        #expect(p["status"] as? String == "waiting on me" && Set(p.keys) == ["name", "species", "stage", "mood", "tools", "status"])
        #expect(!StreamOverlay.plateAllowed(streamMode: true) && StreamOverlay.plateAllowed(streamMode: false))
    }

    @Test func postcardTextLeavesOutPathsReposAndMoney() {
        var w = WeekCounts(); w.runs = 14; w.bugs = 3; w.trick = "backflip"; w.outfit = ["beanie", "scarf"]
        let lines = Postcard.lines(name: "Mochi", species: "bean", w: w)
        #expect(lines == ["Mochi the bean", "This week: watched 14 runs, caught 3 bugs.", "Learned a trick: backflip.", "Wore: beanie, scarf."])
        let all = lines.joined(separator: " ")
        #expect(all.range(of: #"(/|\$|\bNEAR\b|\.swift|\.ts|github|sponsor)"#, options: .regularExpression) == nil)
        #expect(Postcard.render(lines: lines, pet: nil, accent: CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)) != nil)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let sunday6pm = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 18, minute: 5))!
        #expect(Postcard.due(now: sunday6pm, lastSent: nil, calendar: cal))
        #expect(!Postcard.due(now: sunday6pm.addingTimeInterval(-3600), lastSent: nil, calendar: cal))
        #expect(!Postcard.due(now: sunday6pm, lastSent: sunday6pm.addingTimeInterval(-60), calendar: cal))
    }
}
