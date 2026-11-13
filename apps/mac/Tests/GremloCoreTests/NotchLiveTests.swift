import Foundation
import Testing
@testable import GremloCore

@Suite struct PriorityTests {
    let now = Date(timeIntervalSince1970: 1000)
    func with(_ f: (inout NotchLive.Inputs) -> Void) -> LiveState { var i = NotchLive.Inputs(); f(&i); return NotchLive.resolve(i, now: now) }

    @Test func resolverTableFollowsTheSpecOrder() {
        #expect(with { _ in } == .rest)
        #expect(with { $0.sleeping = true } == .sleep)
        #expect(with { $0.sleeping = true; $0.thinking = true } == .think)
        #expect(with { $0.thinking = true; $0.focus = true } == .focus)
        #expect(with { $0.focus = true; $0.egg = true } == .egg)
        #expect(with { $0.egg = true; $0.toolRunning = true } == .peek)
        #expect(with { $0.toolRunning = true; $0.hoverOrPin = true } == .ticker)
        #expect(with { $0.hoverOrPin = true; $0.doneUntil = now.addingTimeInterval(2) } == .done)
        #expect(with { $0.doneUntil = now.addingTimeInterval(-1); $0.toolRunning = true } == .peek, "done folds after 4 s")
        #expect(with { $0.doneUntil = now.addingTimeInterval(2); $0.visitor = true } == .visitor)
        #expect(with { $0.visitor = true; $0.roomOpen = true } == .room)
        #expect(with { $0.roomOpen = true; $0.offline = true } == .offline)
        #expect(with { $0.offline = true; $0.waiting = 1 } == .knock, "approvals still work offline")
        #expect(with { $0.waiting = 3 } == .queue)
        #expect(with { $0.offline = true; $0.stuck = true } == .stuck && with { $0.stuck = true; $0.waiting = 1 } == .knock)
        #expect(with { $0.meetingSoon = true; $0.doneUntil = now.addingTimeInterval(2) } == .meeting && with { $0.meetingSoon = true; $0.visitor = true } == .visitor)
        #expect(with { $0.waiting = 2; $0.dragging = true } == .drop)
    }

    @Test func sizesFromTheSpec() {
        #expect(NotchLive.size(.rest) == (190, 32) && NotchLive.size(.knock) == (660, 150) && NotchLive.size(.offline) == (360, 36))
        #expect(NotchLive.size(.queue, agents: 2).h == 152 && NotchLive.size(.queue, agents: 9).h == 244, "max 4 rows")
    }
}

@Suite struct ApprovalTests {
    let t = Date(timeIntervalSince1970: 1000)

    @Test func riskyCommandsGetNoShortcut() {
        let risky = ["rm -rf build", "git push origin main", "git reset --hard HEAD~1", "npm publish", "docker push x",
                     "find . -name '*.o' -delete", "psql -c 'DROP TABLE users'", "near tokens a.testnet send-near b '1 NEAR'",
                     "cast send 0xabc", "kubectl delete pod x", "terraform destroy", "/bin/rm -rf build", "git -C repo push --force",
                     "cd x && rm -r y", "sudo make install", "git -c core.x=y push"]
        let ordinary = ["ls -la", "npm test", "git status", "git commit -m 'remove x'", "cat README.md", "echo rm", "grep -r push ."]
        for c in risky { #expect(Risk.isRisky(tool: "Bash", input: ["command": c]), "\(c)") }
        for c in ordinary { #expect(!Risk.isRisky(tool: "Bash", input: ["command": c]), "\(c)") }
        #expect(Risk.isRisky(tool: "mcp__wallet__transfer", input: [:]))
        #expect(!Risk.isRisky(tool: "Edit", input: ["file_path": "/tmp/a"]))
        let r = ApprovalRequest.from(id: "1", payload: ["tool_name": "Bash", "tool_input": ["command": "git push"], "session_id": "s"], now: t)
        #expect(!ApprovalQueue.shortcutAllowed(r))
        #expect(ApprovalQueue.shortcutAllowed(ApprovalRequest.from(id: "2", payload: ["tool_name": "Bash", "tool_input": ["command": "npm test"]], now: t)))
    }

    @Test func decisionJSONMatchesTheHooksReference() throws {
        let suggestions: [[String: Any]] = [["type": "addRules", "rules": [["toolName": "Bash", "ruleContent": "npm test"]], "behavior": "allow", "destination": "localSettings"],
                                            ["type": "setMode", "mode": "acceptEdits", "destination": "session"]]
        func decode(_ d: Data) throws -> [String: Any] {
            let o = try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any])
            let h = try #require(o["hookSpecificOutput"] as? [String: Any])
            #expect(h["hookEventName"] as? String == "PermissionRequest")
            return try #require(h["decision"] as? [String: Any])
        }
        #expect(try decode(Decision.json(.allowOnce, suggestions: suggestions)) as NSDictionary == ["behavior": "allow"])
        let always = try decode(Decision.json(.alwaysAllow, suggestions: suggestions))
        #expect(always["behavior"] as? String == "allow")
        #expect((always["updatedPermissions"] as? [[String: Any]])?.count == 1, "only Claude Code's own allow-rule suggestion")
        let deny = try decode(Decision.json(.deny, suggestions: []))
        #expect(deny["behavior"] as? String == "deny" && deny["message"] != nil && deny["interrupt"] == nil)
        let r = ApprovalRequest.from(id: "1", payload: ["tool_name": "Bash", "tool_input": ["command": "npm test"], "permission_suggestions": suggestions], now: t)
        #expect(r.canAlwaysAllow && r.summary == "npm test")
    }

    @Test func oldestFirstAndATerminalAnswerGreysTheRowOut() {
        var q = ApprovalQueue()
        q.add(ApprovalRequest.from(id: "b", payload: ["tool_name": "Edit", "session_id": "s1"], now: t.addingTimeInterval(5)))
        q.add(ApprovalRequest.from(id: "a", payload: ["tool_name": "Bash", "session_id": "s1"], now: t))
        q.add(ApprovalRequest.from(id: "c", payload: ["tool_name": "Bash", "session_id": "s2"], now: t.addingTimeInterval(9)))
        #expect(q.waiting.map(\.id) == ["a", "b", "c"])
        #expect(q.sawEvent(session: "s1", tool: "Bash", event: "PostToolUse") == ["a"], "answered in the terminal")
        #expect(q.waiting.map(\.id) == ["b", "c"])
        #expect(q.sawEvent(session: "s1", tool: nil, event: "Notification").isEmpty)
        #expect(q.sawEvent(session: "s1", tool: "Edit", event: "PreToolUse").isEmpty, "PreToolUse comes before the permission check")
        #expect(q.sawEvent(session: "s2", tool: nil, event: "Stop") == ["c"], "the run ended: release what's left")
        q.remove("b")
        #expect(q.waiting.isEmpty)
    }
}

@Suite struct UsageTests {
    @Test func transcriptReaderSumsUsageAcrossPartialChunks() {
        var r = TranscriptUsageReader()
        let l1 = #"{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":3000,"cache_read_input_tokens":50000}}}"#
        let l2 = #"{"type":"user","message":{"content":"hi"}}"#
        let l3 = #"{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":5}}}"#
        let all = l1 + "\n" + l2 + "\n" + l3 + "\n"
        let cut = all.index(all.startIndex, offsetBy: 40)
        r.feed(String(all[..<cut])); r.feed(String(all[cut...]))
        #expect(r.usage.input == 1010 && r.usage.output == 205 && r.usage.cacheWrite == 3000 && r.usage.cacheRead == 50000)
        #expect(r.usage.model == "claude-opus-5-5")
    }

    @Test func costIsAnEstimateAndUnknownIsADash() {
        var u = Usage(); u.input = 1_000_000; u.output = 100_000; u.model = "claude-opus-5-5"
        #expect(Prices.costMicroCents(u) == 1_000_000 * 400 + 100_000 * 2000)
        #expect(Prices.label(u) == "$6.00 est")
        var m = u; m.model = "claude-opus-5-5[1m]"
        #expect(Prices.entry(m.model!)?.prefix == "claude-opus-5-5", "longest prefix wins over claude-opus-5")
        var x = u; x.model = "some-other-model"
        #expect(Prices.label(x) == "\u{2014}" && Prices.label(nil) == "\u{2014}" && Prices.label(Usage()) == "\u{2014}", "never $0.00 for missing data")
        #expect(SoftAlert.due(costMicroCents: 500 * 1_000_000, limitCents: 500) && !SoftAlert.due(costMicroCents: 499 * 1_000_000, limitCents: 500))
        #expect(!SoftAlert.due(costMicroCents: nil, limitCents: 100) && !SoftAlert.due(costMicroCents: 10, limitCents: nil))
    }
}
