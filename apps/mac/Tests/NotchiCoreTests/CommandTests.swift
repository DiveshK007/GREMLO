import Foundation
import Testing
@testable import NotchiCore

@Suite struct CommandTests {
    @Test func durations() {
        #expect(Commands.minutes("30") == 30 && Commands.minutes("30m") == 30 && Commands.minutes("2h") == 120)
        #expect(Commands.minutes("1h30m") == 90 && Commands.minutes("90s") == 2 && Commands.minutes("x") == nil && Commands.minutes("0") == nil)
    }

    @Test func parsing() throws {
        #expect(try Commands.parse(["status", "--json"], cwd: "/r") == Request("status", ["json": "1"]))
        #expect(try Commands.parse(["say", "tests", "are", "green"], cwd: "/r") == Request("say", ["text": "tests are green"]))
        #expect(throws: CommandError.self) { try Commands.parse(["say", String(repeating: "x", count: 81)], cwd: "/") }
        #expect(try Commands.parse(["pause"], cwd: "/") == Request("pause", ["min": "30"]))
        #expect(try Commands.parse(["pause", "2h"], cwd: "/") == Request("pause", ["min": "120"]))
        #expect(throws: CommandError.self) { try Commands.parse(["focus", "40m"], cwd: "/") }
        #expect(try Commands.parse(["pet", "pip", "--agent", "abc"], cwd: "/") == Request("pet", ["species": "notchi-pip", "agent": "abc"]))
        #expect(try Commands.parse(["approve", "next"], cwd: "/") == Request("approve", ["answer": "allow"]))
        #expect(try Commands.parse(["hook", "install", "git", "--global"], cwd: "/repo") == Request("hook", ["action": "install", "agent": "git", "cwd": "/repo", "global": "1"]))
        #expect(try Commands.parse(["preview", "mypet"], cwd: "/work") == Request("preview", ["dir": "/work/mypet"]))
        for bad in [["pay"], ["payout", "x"], ["spend"], ["approve", "all"]] {
            #expect(throws: CommandError.self, "\(bad)") { try Commands.parse(bad, cwd: "/") }
        }
    }

    @Test func urlSchemeCanOnlyDoTheSafeThings() {
        #expect(Commands.fromURL(URL(string: "notchi://say?text=hello%20there")!) == Request("say", ["text": "hello there"]))
        #expect(Commands.fromURL(URL(string: "notchi://pause?min=30")!) == Request("pause", ["min": "30"]))
        #expect(Commands.fromURL(URL(string: "notchi://focus?min=25")!) == Request("focus", ["min": "25"]))
        #expect(Commands.fromURL(URL(string: "notchi://approve?answer=allow")!) == nil, "no approvals from a link")
        #expect(Commands.fromURL(URL(string: "notchi://hook?action=install")!) == nil)
        #expect(Commands.fromURL(URL(string: "https://say?text=x")!) == nil)
        #expect(Commands.fromURL(URL(string: "notchi://visit?to=" + String(repeating: "a", count: 24))!) == Request("visit", ["to": String(repeating: "a", count: 24)]))
        #expect(Commands.fromURL(URL(string: "notchi://visit?to=../x")!) == nil)
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
        try FileManager.default.copyItem(at: pets.appendingPathComponent("notchi/pet.json"), to: bad.appendingPathComponent("pet.json"))
        #expect(PackCheck.problems(bad).contains { $0.hasPrefix("spritesheet") })
    }
}

@Suite struct SocketTests {
    @Test func roundTripOverTheSocketIsUserOnly() throws {
        let path = "/tmp/notchi-test-\(UUID().uuidString.prefix(8)).sock"
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
