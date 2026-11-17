import Foundation
import Testing
@testable import GremloCore

@Suite struct HookAuthTests {
    let secret = String(repeating: "ab", count: 32)

    @Test func parsesHeadersCaseInsensitively() {
        let h = HookAuth.parseHead("POST /claude/hook HTTP/1.1\r\nHost: 127.0.0.1:47474\r\nX-Gremlo-Secret: \(secret)\r\nContent-Length: 2")
        #expect(h["host"] == "127.0.0.1:47474")
        #expect(h["x-gremlo-secret"] == secret)
    }

    @Test func claudeEventsNeedTheSecret() {
        let ok = ["host": "127.0.0.1:47474", "x-gremlo-secret": secret]
        #expect(HookAuth.refusal(headers: ok, secret: secret, needsSecret: true) == nil)
        #expect(HookAuth.refusal(headers: ["host": "127.0.0.1:47474"], secret: secret, needsSecret: true) != nil)
        #expect(HookAuth.refusal(headers: ["x-gremlo-secret": String(repeating: "cd", count: 32)], secret: secret, needsSecret: true) != nil)
        #expect(HookAuth.refusal(headers: ["x-gremlo-secret": "short"], secret: secret, needsSecret: true) != nil)
    }

    @Test func browsersAndOtherHostsAreRefusedEvenWithTheSecret() {
        #expect(HookAuth.refusal(headers: ["origin": "https://evil.example", "x-gremlo-secret": secret], secret: secret, needsSecret: true) != nil)
        #expect(HookAuth.refusal(headers: ["host": "evil.example:47474", "x-gremlo-secret": secret], secret: secret, needsSecret: true) != nil)
        #expect(HookAuth.refusal(headers: ["origin": "null"], secret: secret, needsSecret: false) != nil)
    }

    @Test func gitHooksFromBeforeTheSecretStillWork() {
        #expect(HookAuth.refusal(headers: ["host": "127.0.0.1:47474"], secret: secret, needsSecret: false) == nil)
    }

    @Test func secretIsCreatedOnceKeptPrivateAndRewrittenIfDamaged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gremlo-auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try HookAuth.loadOrCreate(in: dir)
        #expect(a.count == 64 && a.allSatisfy(\.isHexDigit))
        #expect(try HookAuth.loadOrCreate(in: dir) == a)
        let header = try String(contentsOf: dir.appendingPathComponent("hook-header"), encoding: .utf8)
        #expect(header == "X-Gremlo-Secret: \(a)")
        let mode = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("hook-secret").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try Data("junk".utf8).write(to: dir.appendingPathComponent("hook-secret"))
        #expect(try HookAuth.loadOrCreate(in: dir) != a)
    }

    @Test func slidingLimitDropsTheBurstAndRecovers() {
        let l = SlidingLimit(max: 3, window: 60)
        let t = Date(timeIntervalSince1970: 1000)
        #expect([0, 1, 2, 3].map { l.allow(t.addingTimeInterval(Double($0))) } == [true, true, true, false])
        #expect(l.allow(t.addingTimeInterval(61)))
    }
}
