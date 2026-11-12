import CryptoKit
import Foundation

// `notchi verify <campaign>` (R2 §16): replays a campaign's public log. Every entry must carry a valid device
// signature over the exact report it counts, the hash chain must be unbroken, and the logged sightings must equal
// what was billed (settled + pending + held + voided by the fraud rules).

public struct PublicLog: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let i: Int, campaign: String, hour: Int, counts: [Int], pet: String
        public let key: String?, time: String?, sig: String?, body: String, prev: String, hash: String
    }
    public struct Billed: Codable, Sendable { public let settled: Int, pending: Int, held: Int, voided: Int }
    public let campaign: String
    public let entries: [Entry]
    public let billed: Billed
}

public enum LogVerify {
    static func hex(_ d: some Swift.Sequence<UInt8>) -> String { d.map { String(format: "%02x", $0) }.joined() }
    static func sha(_ s: String) -> String { hex(SHA256.hash(data: Data(s.utf8))) }
    static func b64u(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    /// Must match apps/server/src/trust.ts entryHash.
    public static func entryHash(_ e: PublicLog.Entry) -> String {
        sha([e.prev, "\(e.i)", e.campaign, "\(e.hour)", e.counts.map(String.init).joined(separator: ","), e.pet,
             e.key ?? "", e.time ?? "", e.sig ?? "", sha(e.body)].joined(separator: "|"))
    }

    /// Must match apps/server/src/auth.ts canonical() for POST /impressions.
    public static func signatureOK(_ e: PublicLog.Entry) -> Bool {
        guard let k = e.key.flatMap(b64u), let s = e.sig.flatMap(b64u), let t = e.time,
              let key = try? P256.Signing.PublicKey(x963Representation: k), let sig = try? P256.Signing.ECDSASignature(derRepresentation: s) else { return false }
        return key.isValidSignature(sig, for: Data("POST\n/impressions\n\(t)\n\(sha(e.body))".utf8))
    }

    public struct Result: Equatable, Sendable { public let ok: Bool; public let logged: Int; public let billed: Int; public let problems: [String] }

    public static func run(_ log: PublicLog) -> Result {
        var problems: [String] = [], prev = String(repeating: "0", count: 64), total = 0
        for (n, e) in log.entries.enumerated() {
            if e.i != n { problems.append("entry \(n): index \(e.i)") }
            if e.prev != prev { problems.append("entry \(n): broken chain") }
            if entryHash(e) != e.hash { problems.append("entry \(n): hash doesn't match") }
            if e.key == nil { problems.append("entry \(n): unsigned report") } else if !signatureOK(e) { problems.append("entry \(n): bad signature") }
            if e.campaign != log.campaign { problems.append("entry \(n): another campaign") }
            // the signed report must contain at least as many rows for this campaign as the entry counts
            let rows = ((try? JSONSerialization.jsonObject(with: Data(e.body.utf8))) as? [String: Any])?["impressions"] as? [[String: Any]] ?? []
            let mine = rows.filter { "\($0["campaignId"] ?? "")" == log.campaign }.count
            let counted = e.counts.reduce(0, +)
            if counted > mine { problems.append("entry \(n): counts \(counted) but the signed report has \(mine)") }
            total += counted
            prev = e.hash
        }
        let b = log.billed, billed = b.settled + b.pending + b.held + b.voided
        if total != billed { problems.append("the log has \(total) sightings, the bill accounts for \(billed)") }
        return Result(ok: problems.isEmpty, logged: total, billed: billed, problems: problems)
    }
}
