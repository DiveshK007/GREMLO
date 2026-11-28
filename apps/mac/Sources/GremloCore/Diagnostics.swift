import Foundation

// Opt-in diagnostics (Settings, Privacy): which failures happened how often, and what a crash looked like. Built
// here so the exact fields are tested; the server (apps/server/src/diagnostics.ts) refuses anything else.

public enum Diagnostics {
    /// The failures that are counted. Same list as COUNTS on the server.
    public enum Count: String, CaseIterable, Sendable {
        case viewRefused, viewNotSent, thinkFailed, serverUnreachable, settleStuck, parkFailed

        public var plain: String {
            switch self {
            case .viewRefused: return "views the server refused"
            case .viewNotSent: return "views that couldn't be sent"
            case .thinkFailed: return "thoughts that failed"
            case .serverUnreachable: return "times the server couldn't be reached"
            case .settleStuck: return "times payments were stuck"
            case .parkFailed: return "park joins that failed"
            }
        }
    }

    public struct Crash: Equatable, Sendable {
        public let type: String
        public let signal: String?
        public let frames: [String]  // "Image: symbol", the crashed thread, top first
    }

    /// The crash signature from a macOS .ips report (a JSON header line, then a JSON body): exception type, signal
    /// and the crashed thread's symbol names. Paths, ids, other threads and registers are never read out.
    public static func crash(ips: String) -> Crash? {
        guard let nl = ips.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(ips[ips.index(after: nl)...].utf8)) as? [String: Any],
              let exc = body["exception"] as? [String: Any], let type = exc["type"] as? String else { return nil }
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        let thread = (body["threads"] as? [[String: Any]] ?? []).first { $0["triggered"] as? Bool == true }
        let frames = (thread?["frames"] as? [[String: Any]] ?? []).compactMap { f -> String? in
            // a symbol never needs a path, and a path would carry the user's name: cut at the first slash
            guard let sym = (f["symbol"] as? String)?.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first?
                .trimmingCharacters(in: .whitespaces), !sym.isEmpty else { return nil }
            let i = f["imageIndex"] as? Int ?? -1
            return clean("\(images.indices.contains(i) ? images[i] : "?"): \(sym)")
        }
        // a type or signal can carry extra words ("SIGKILL (Code Signature Invalid)"): keep the leading name only, as the server expects
        guard let t = word(type, prefix: "", max: 40) else { return nil }
        return Crash(type: t, signal: (exc["signal"] as? String).flatMap { word($0, prefix: "SIG", max: 13) }, frames: Array(frames.prefix(12)))
    }

    /// The first word if it is only A-Z, 0-9 and _, starts with `prefix` and fits `max`; nil otherwise.
    static func word(_ s: String, prefix: String, max: Int) -> String? {
        let w = String(s.prefix { $0 != " " && $0 != "(" })
        let ok = !w.isEmpty && w.count <= max && w.hasPrefix(prefix) && w.count > prefix.count && w.allSatisfy { ($0.isASCII && ($0.isUppercase || $0.isNumber)) || $0 == "_" }
        return ok ? w : nil
    }

    /// Only the characters the server accepts; anything else becomes "_".
    static func clean(_ s: String, max: Int = 160) -> String {
        let ok = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_$.:<>()[], &*-")
        return String(String(s.map { ok.contains($0) ? $0 : "_" }).prefix(max))
    }

    /// The whole report, exactly as sent.
    public static func report(version: String, os: String, arch: String, counts: [String: Int], crashes: [Crash]) -> [String: Any] {
        [
            "version": version, "os": os, "arch": arch,
            "counts": counts.filter { k, v in v > 0 && Count(rawValue: k) != nil },
            "crashes": crashes.prefix(5).map { c -> [String: Any] in
                var d: [String: Any] = ["type": c.type, "frames": c.frames]
                if let s = c.signal { d["signal"] = s }
                return d
            },
        ]
    }
}
