import Foundation
import Testing
@testable import NotchiCore

@Suite struct HuntTests {
    let t = Date(timeIntervalSince1970: 10_000)

    @Test func testRunOutcomes() {
        #expect(TestRun.outcome(event: "PostToolUseFailure", tool: "Bash", command: "npm test") == false)
        #expect(TestRun.outcome(event: "PostToolUse", tool: "Bash", command: "cargo test --all") == true)
        #expect(TestRun.outcome(event: "PostToolUse", tool: "Bash", command: "ls") == nil)
        #expect(TestRun.outcome(event: "PostToolUseFailure", tool: "Bash", command: "pytest -x", interrupted: true) == nil)
        #expect(TestRun.outcome(event: "PostToolUse", tool: "Edit", command: nil) == nil)
    }

    @Test func bugLifecycle() {
        var h = BugHunt()
        #expect(h.failed(at: 100) != nil && h.failed(at: 400) != nil && h.failed(at: 250) != nil)
        #expect(h.failed(at: 50) == nil && h.bugs.count == 3, "4th fail: still 3")
        let squashed = h.bugs[1].id
        #expect(h.squash(squashed) && h.bugs.count == 2)
        let eaten = h.passed(petX: 380)
        #expect(eaten.map(\.x) == [250, 100], "nearest first (the one at 400 was squashed)")
        #expect(h.jar == 2 && h.bugs.isEmpty, "the squashed one doesn't count")
        _ = h.failed(at: 10); h.clear()
        #expect(h.bugs.isEmpty && h.jar == 2, "screen share: all gone, jar unchanged")
    }

    @Test func stuckNormaliserAndTriggers() {
        let a = "Exit code 1\nTypeError: Cannot read properties of undefined (reading 'x') at /Users/a/app/src/index.ts:12:5"
        let b = "Exit code 2\nTypeError: Cannot read properties of undefined (reading 'x') at /Users/b/other/main.ts:98:1"
        #expect(StuckDetector.normalise(a) == StuckDetector.normalise(b), "differ only in numbers and paths")
        #expect(StuckDetector.normalise("error at 2026-11-03T10:22:01Z id 0xdeadbeef") == StuckDetector.normalise("error at 2026-11-04T09:00:59Z id 0x1"))
        #expect(StuckDetector.normalise(a) != StuckDetector.normalise("Exit code 1\nReferenceError: y is not defined"))
        var s = StuckDetector()
        for i in 0..<4 { #expect(s.failure(tool: "Bash", error: a, at: t.addingTimeInterval(Double(i) * 60)) == nil) }
        let trig = s.failure(tool: "Bash", error: b, at: t.addingTimeInterval(7 * 60))
        #expect(trig?.count == 5 && trig?.line.hasPrefix("TypeError") == true)
        #expect(StuckDetector.title(trig!, now: t.addingTimeInterval(7 * 60)) == "Going in circles \u{00B7} same error 5\u{00D7} \u{00B7} 7 min")
        var slow = StuckDetector()
        for i in 0..<5 { #expect(slow.failure(tool: "Bash", error: a, at: t.addingTimeInterval(Double(i) * 200)) == nil, "spread over 13 minutes") }
        var ig = StuckDetector(); ig.ignoreRun()
        for _ in 0..<6 { #expect(ig.failure(tool: "Bash", error: a, at: t) == nil) }
        ig.runEnded()
        var e = StuckDetector()
        let seq = ["h0", "h1", "h0", "h1", "h0"]
        let out = seq.map { e.edited(file: "/r/a.swift", hash: $0, at: t) }
        #expect(out.prefix(4).allSatisfy { $0 == nil } && out[4]?.kind == .editRevert && out[4]?.line == "a.swift")
        #expect(StuckDetector.nudge == "You've hit this error 5 times. Explain the cause before trying again.")
    }

    @Test func dropZoneQuotesSpaces() {
        #expect(DropZone.text(paths: ["/a/b.txt", "/My Files/c d.png"]) == "/a/b.txt\n\"/My Files/c d.png\"")
        #expect(DropZone.isImage("/x/Shot 1.PNG") && !DropZone.isImage("/x/notes.md"))
    }

    @Test func dreamsTricksSeasonsMeetings() {
        var d = DreamLog()
        for x in [Dream.wrench, .wrench, .flask, .bug, .wrench, .heart] { d.add(x) }
        #expect(d.icons == [.wrench, .flask, .bug, .wrench, .heart, .moon], "repeats collapse, moon last")
        #expect(d.summary(name: "Mochi") == "Mochi is dreaming about 3 edits and one stubborn test.")
        #expect(DreamLog().summary(name: "Mochi") == "Mochi is dreaming.")
        #expect(Trick.learned(approvals: 25, maxSessionTools: 99, releaseTags: 1) == [.backflip, .moonwalk])
        #expect(Trick.mayShowOff(last: nil, now: t, idle: true) && !Trick.mayShowOff(last: t.addingTimeInterval(-3599), now: t, idle: true))
        #expect(!Trick.mayShowOff(last: nil, now: t, idle: false))
        let f = ISO8601DateFormatter(); f.timeZone = .current
        func day(_ s: String) -> Date { f.date(from: s + "T12:00:00Z")! }
        #expect(Season.current(day("2026-11-08"), region: "IN") == .diwali)
        #expect(Season.current(day("2026-11-08"), region: "US") == nil)
        #expect(Season.current(day("2026-10-12"), region: "US") == .october)
        #expect(Season.current(day("2027-01-10"), region: "GB") == .winter && Season.current(day("2027-01-10"), region: "AU") == nil)
        #expect(Season.current(day("2027-07-10"), region: "AU") == .winter)
        let start = t.addingTimeInterval(240)
        #expect(HeadsUp.state(start: start, end: start.addingTimeInterval(1800), now: t) == .soon(minutes: 4))
        #expect(HeadsUp.state(start: start, end: start.addingTimeInterval(1800), now: start) == .inMeeting)
        #expect(HeadsUp.state(start: t.addingTimeInterval(400), end: t.addingTimeInterval(900), now: t) == HeadsUp.none)
    }

    @Test func tolerantDecodingKeepsSavedProgress() throws {
        let old = #"{"name":"Mochi","meals":["a","b"],"stage":1,"toolCalls":7}"#
        let p = try #require(Tolerant.decode(PetProgress.self, from: Data(old.utf8), defaults: PetProgress()))
        #expect(p.meals == ["a", "b"] && p.toolCalls == 7 && p.bugJar == 0 && p.stage == .hatchling)
    }
}

@Suite(.serialized) struct GitHookTests {
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/Notchi/Resources/notchi-git-hook.sh").standardized

    @discardableResult
    func sh(_ cmd: String, in dir: URL, env: [String: String] = [:]) throws -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        p.currentDirectoryURL = dir
        var e = ProcessInfo.processInfo.environment
        e.merge(["GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null"]) { _, n in n }
        e.merge(env) { _, n in n }
        p.environment = e
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func installChainsCommitForcePushTagAndRemove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchi-git-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("repo"), remote = root.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sink = root.appendingPathComponent("sink").path, mine = root.appendingPathComponent("mine").path
        let env = ["NOTCHI_GIT_SINK": sink]
        try sh("git init -q -b main . && git init -q --bare ../remote.git && git remote add origin ../remote.git", in: repo)
        // the user's own post-commit hook must keep running
        try "#!/bin/sh\necho ran >> \(mine)\n".write(toFile: repo.path + "/.git/hooks/post-commit", atomically: true, encoding: .utf8)
        try sh("chmod +x .git/hooks/post-commit", in: repo)
        try GitHooks.install(repo: repo.path, script: script)
        try GitHooks.install(repo: repo.path, script: script)  // twice is harmless
        try sh("echo a > a && git add a && git commit -qm one && git push -q origin main", in: repo, env: env)
        try sh("echo b > b && git add b && git commit -qm two && git push -q origin main && git reset -q --hard HEAD~1 && echo c > c && git add c && git commit -qm three && git push -qf origin main", in: repo, env: env)
        try sh("git tag v1.0.0 && git tag nightly", in: repo, env: env)
        let lines = try String(contentsOfFile: sink, encoding: .utf8).split(separator: "\n").map(String.init)
        let events = lines.compactMap { l in (try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any]).flatMap(GitEvent.parse) }
        #expect(events == [.commit, .commit, .commit, .forcePush, .tag], "\(lines)")
        #expect(lines.allSatisfy { !$0.contains(repo.path) && !$0.contains("one") }, "no paths, no messages")
        #expect(try String(contentsOfFile: mine, encoding: .utf8) == "ran\nran\nran\n", "the existing hook ran each commit")
        try GitHooks.remove(repo: repo.path)
        #expect(try String(contentsOfFile: repo.path + "/.git/hooks/post-commit", encoding: .utf8).contains("echo ran"), "original restored")
        #expect(!FileManager.default.fileExists(atPath: repo.path + "/.git/hooks/pre-push"))
    }

    @Test func mergeHeadWatcher() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("notchi-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        try sh("git init -q -b main . && echo a > f && git add f && git commit -qm a && git checkout -qb x && echo b > f && git commit -qam b && git checkout -q main && echo c > f && git commit -qam c", in: repo)
        #expect(!GitWatch.conflicted(repo.appendingPathComponent("sub").path))
        try sh("git merge x", in: repo)
        #expect(GitWatch.conflicted(repo.appendingPathComponent("sub").path), "MERGE_HEAD while conflicted, found from a subdirectory")
        try sh("git merge --abort", in: repo)
        #expect(!GitWatch.conflicted(repo.path))
    }
}
