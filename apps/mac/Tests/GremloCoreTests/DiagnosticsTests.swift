import Foundation
import Testing
@testable import GremloCore

struct DiagnosticsTests {
    // the shape of a real .ips: a header line, then the body; the paths and ids must never come out
    let ips = """
    {"app_name":"Gremlo","app_version":"1.1.0","bundleID":"app.gremlo.mac","os_version":"macOS 15.2"}
    {"crashReporterKey":"ABCD-1234","procPath":"/Users/someone/Applications/Gremlo.app/Contents/MacOS/Gremlo",
     "exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},
     "usedImages":[{"name":"Gremlo","path":"/Users/someone/Applications/Gremlo.app/Contents/MacOS/Gremlo"},{"name":"AppKit"}],
     "threads":[{"frames":[{"imageIndex":1,"symbol":"other thread"}]},
                {"triggered":true,"frames":[{"imageIndex":0,"symbol":"Backend.render() /Users/someone/x.swift"},{"imageIndex":1,"symbol":"-[NSApplication run]"},{"imageIndex":0}]}]}
    """

    @Test func crashKeepsTheSignatureAndNothingElse() {
        let c = Diagnostics.crash(ips: ips)
        #expect(c?.type == "EXC_BREAKPOINT" && c?.signal == "SIGTRAP")
        #expect(c?.frames == ["Gremlo: Backend.render()", "AppKit: -[NSApplication run]"], "the crashed thread only, cut before any path")
        #expect(!(c?.frames.joined().contains("someone") ?? true))
        #expect(Diagnostics.crash(ips: "not a report") == nil)
    }

    @Test func reportHasOnlyTheKnownFields() {
        let r = Diagnostics.report(version: "1.1.0", os: "15.2", arch: "arm64", counts: ["viewRefused": 2, "thinkFailed": 0, "somethingElse": 4], crashes: [])
        #expect(Set(r.keys) == ["version", "os", "arch", "counts", "crashes"])
        #expect(r["counts"] as? [String: Int] == ["viewRefused": 2], "zero and unknown counts are dropped")
        #expect(Diagnostics.Count.allCases.map(\.rawValue) == ["viewRefused", "viewNotSent", "thinkFailed", "serverUnreachable", "settleStuck", "parkFailed"], "the server keeps the same list")
    }
}
