import Foundation
import Testing
@testable import GremloCore

@Suite struct CommandTests {
    @Test func onePetNameRule() {
        #expect(PetName.valid("mochi") && PetName.valid("mochi-2") && PetName.valid(String(repeating: "a", count: 24)))
        #expect(!PetName.valid("m") && !PetName.valid(String(repeating: "a", count: 25)) && !PetName.valid("Mochi") && !PetName.valid("mochi.gremlo") && !PetName.valid("-mochi") && !PetName.valid("mochi-"))
        #expect(PetName.clean(" Mochi ") == "mochi" && PetName.clean("mo chi") == nil)
    }

    @Test func durations() {
        #expect(Commands.minutes("30") == 30 && Commands.minutes("30m") == 30 && Commands.minutes("2h") == 120)
        #expect(Commands.minutes("1h30m") == 90 && Commands.minutes("90s") == 2 && Commands.minutes("x") == nil && Commands.minutes("0") == nil)
        #expect(Commands.minutes("99999999999999999999m") == nil && Commands.minutes("99999999999999999999") == nil && Commands.minutes("10081") == nil, "no trap on huge values")
        #expect(Commands.fromURL(URL(string: "gremlo://pause?min=99999999999999999999m")!) == nil)
    }

    @Test func parsing() throws {
        #expect(try Commands.parse(["status", "--json"], cwd: "/r") == Request("status", ["json": "1"]))
        #expect(try Commands.parse(["say", "tests", "are", "green"], cwd: "/r") == Request("say", ["text": "tests are green"]))
        #expect(throws: CommandError.self) { try Commands.parse(["say", String(repeating: "x", count: 81)], cwd: "/") }
        #expect(try Commands.parse(["pause"], cwd: "/") == Request("pause", ["min": "30"]))
        #expect(try Commands.parse(["pause", "2h"], cwd: "/") == Request("pause", ["min": "120"]))
        #expect(throws: CommandError.self) { try Commands.parse(["focus", "40m"], cwd: "/") }
        #expect(try Commands.parse(["pet", "pip", "--agent", "abc"], cwd: "/") == Request("pet", ["species": "gremlo-pip", "agent": "abc"]))
        #expect(try Commands.parse(["approve", "next"], cwd: "/") == Request("approve", ["answer": "allow"]))
        #expect(try Commands.parse(["hook", "install", "git", "--global"], cwd: "/repo") == Request("hook", ["action": "install", "agent": "git", "cwd": "/repo", "global": "1"]))
        #expect(try Commands.parse(["preview", "mypet"], cwd: "/work") == Request("preview", ["dir": "/work/mypet"]))
        for bad in [["pay"], ["payout", "x"], ["spend"], ["approve", "all"]] {
            #expect(throws: CommandError.self, "\(bad)") { try Commands.parse(bad, cwd: "/") }
        }
    }

    @Test func urlSchemeCanOnlyDoTheSafeThings() {
        #expect(Commands.fromURL(URL(string: "gremlo://say?text=hello%20there")!) == Request("say", ["text": "hello there"]))
        #expect(Commands.fromURL(URL(string: "gremlo://pause?min=30")!) == Request("pause", ["min": "30"]))
        #expect(Commands.fromURL(URL(string: "gremlo://focus?min=25")!) == Request("focus", ["min": "25"]))
        #expect(Commands.fromURL(URL(string: "gremlo://approve?answer=allow")!) == nil, "no approvals from a link")
        #expect(Commands.fromURL(URL(string: "gremlo://hook?action=install")!) == nil)
        #expect(Commands.fromURL(URL(string: "https://say?text=x")!) == nil)
        #expect(Commands.fromURL(URL(string: "gremlo://visit?to=" + String(repeating: "a", count: 24))!) == Request("visit", ["to": String(repeating: "a", count: 24)]))
        #expect(Commands.fromURL(URL(string: "gremlo://visit?to=../x")!) == nil)
    }

    @Test func sayLimiter() {
        var s = SayLimiter()
        let t = Date(timeIntervalSince1970: 0)
        let got = [s.allow(now: t, screenShared: false), s.allow(now: t.addingTimeInterval(9), screenShared: false),
                   s.allow(now: t.addingTimeInterval(11), screenShared: true), s.allow(now: t.addingTimeInterval(12), screenShared: false)]
        #expect(got == [true, false, false, true], "every 10 s, skipped during a share")
    }

    @Test func packCheck() throws {
        let pets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../assets/pets").standardized
        for s in Roster.all { #expect(PackCheck.problems(pets.appendingPathComponent(s.id)).isEmpty, "\(s.id)") }
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("badpack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bad) }
        #expect(PackCheck.problems(bad) == ["pet.json is missing"])
        try FileManager.default.copyItem(at: pets.appendingPathComponent("gremlo/pet.json"), to: bad.appendingPathComponent("pet.json"))
        #expect(PackCheck.problems(bad).contains { $0.hasPrefix("spritesheet") })
    }
}

@Suite struct SocketTests {
    @Test func roundTripOverTheSocketIsUserOnly() throws {
        let path = "/tmp/gremlo-test-\(UUID().uuidString.prefix(8)).sock"
        defer { unlink(path) }
        let server = CommandSocket(path: path, onMain: false) { r in Reply(ok: r.cmd == "status", text: "got \(r.cmd)", data: ["n": r.args["min"] ?? ""]) }
        #expect(server.listening)
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600, "only this user can talk to the app")
        #expect(CommandClient.send(Request("status"), path: path) == Reply(ok: true, text: "got status", data: ["n": ""]))
        #expect(CommandClient.send(Request("pause", ["min": "30"]), path: path)?.data?["n"] == "30")
        #expect(CommandClient.send(Request("status"), path: "/tmp/nothing-here.sock") == nil)
    }
}

@Suite struct VerifyTests {
    func fixture() throws -> PublicLog {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/campaign-log.json")
        return try JSONDecoder().decode(PublicLog.self, from: Data(contentsOf: url))
    }

    @Test func aLogMadeByTheServerVerifies() throws {
        let r = LogVerify.run(try fixture())
        #expect(r == LogVerify.Result(ok: true, logged: 4, billed: 4, problems: []))
    }

    @Test func tamperingAndBillMismatchesShow() throws {
        let log = try fixture()
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as? [String: Any])
        var entries = json["entries"] as! [[String: Any]]
        entries[2]["counts"] = [3, 0, 0, 0, 0]
        json["entries"] = entries
        let forged = try JSONDecoder().decode(PublicLog.self, from: JSONSerialization.data(withJSONObject: json))
        let r = LogVerify.run(forged)
        #expect(!r.ok && r.problems.contains { $0.contains("entry 2: hash") } && r.problems.contains { $0.contains("signed report has 1") })
        var billed = json; billed["entries"] = (try JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as! [String: Any])["entries"]
        billed["billed"] = ["settled": 5, "pending": 1, "held": 1, "voided": 0]
        let over = LogVerify.run(try JSONDecoder().decode(PublicLog.self, from: JSONSerialization.data(withJSONObject: billed)))
        #expect(over.problems == ["the log has 4 sightings, the bill accounts for 7"])
    }
}

@Suite struct PhoneLinkTests {
    @Test func pairingSealsAndOnlyTheKeyOpens() throws {
        let p = PhonePairing.new(relay: "https://relay.example")
        let back = try #require(PhonePairing.from(code: p.code))
        #expect(back == p && p.channel.count == 32 && p.key.count == 32)
        #expect(PhonePairing.from(code: "gremlo-pair:bm9wZQ==") == nil && PhonePairing.from(code: "hello") == nil)
        let s = PhoneState(name: "Mochi", species: "gremlo", mood: "thriving", running: true, startedAt: Date(timeIntervalSince1970: 100), tools: 3,
                           waiting: [PhoneApproval(id: "a", tool: "Bash", summary: "npm test", risky: false)], quiet: false, doneAt: nil, at: Date(timeIntervalSince1970: 200))
        let box = try p.seal(s)
        #expect(!box.contains("npm test"), "the relay sees ciphertext only")
        #expect(p.open(PhoneState.self, box) == s)
        #expect(PhonePairing.new(relay: "x").open(PhoneState.self, box) == nil, "another pairing can't read it")
    }

    @Test func phoneAnswersOnlyOrdinaryWaitingRequests() {
        let now = Date(timeIntervalSince1970: 1000)
        let waiting = [PhoneApproval(id: "a", tool: "Bash", summary: "npm test", risky: false), PhoneApproval(id: "b", tool: "Bash", summary: "git push", risky: true)]
        #expect(PhoneRules.accept(PhoneAnswer(id: "a", allow: true, at: now), waiting: waiting, now: now)?.id == "a")
        #expect(PhoneRules.accept(PhoneAnswer(id: "b", allow: true, at: now), waiting: waiting, now: now) == nil, "risky: open on the Mac")
        #expect(PhoneRules.accept(PhoneAnswer(id: "c", allow: true, at: now), waiting: waiting, now: now) == nil, "already answered elsewhere")
        #expect(PhoneRules.accept(PhoneAnswer(id: "a", allow: true, at: now.addingTimeInterval(-300)), waiting: waiting, now: now) == nil, "stale")
        #expect(PhoneRules.ring(startedAt: now.addingTimeInterval(-900), now: now) == 0.5)
    }
}
