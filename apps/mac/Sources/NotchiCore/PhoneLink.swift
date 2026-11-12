import CryptoKit
import Foundation

// Phone and Watch (base §10, R4 §17). The Mac seals its state with a key it shares with the phone by QR code; the
// server only relays sealed boxes it can't read. Answers come back the same way. Self-contained (Foundation and
// CryptoKit only) so the iPhone and Watch targets compile this same file.

public struct PhoneApproval: Codable, Equatable, Sendable, Identifiable {
    public let id: String, tool: String, summary: String
    public let risky: Bool   // deletes, pushes or spends: the phone says "Open on the Mac"
    public init(id: String, tool: String, summary: String, risky: Bool) { self.id = id; self.tool = tool; self.summary = summary; self.risky = risky }
}

public struct PhoneState: Codable, Equatable, Sendable {
    public var name: String, species: String, mood: String
    public var running: Bool, startedAt: Date?, tools: Int
    public var waiting: [PhoneApproval]
    public var quiet: Bool          // screen shared or in a meeting: no haptics on the phone or Watch
    public var doneAt: Date?        // the last Stop, for the success haptic
    public var at: Date
    public init(name: String, species: String, mood: String, running: Bool, startedAt: Date?, tools: Int, waiting: [PhoneApproval], quiet: Bool, doneAt: Date?, at: Date) {
        self.name = name; self.species = species; self.mood = mood; self.running = running; self.startedAt = startedAt
        self.tools = tools; self.waiting = waiting; self.quiet = quiet; self.doneAt = doneAt; self.at = at
    }
}

public struct PhoneAnswer: Codable, Equatable, Sendable {
    public let id: String, allow: Bool, at: Date
    public init(id: String, allow: Bool, at: Date) { self.id = id; self.allow = allow; self.at = at }
}

public struct PhonePairing: Codable, Equatable, Sendable {
    public let relay: String     // the server that relays sealed boxes
    public let channel: String   // 32 hex characters: the mailbox name, unguessable
    public let key: Data         // 32 bytes, AES-GCM; never sent to the server

    public init(relay: String, channel: String, key: Data) { self.relay = relay; self.channel = channel; self.key = key }
    public static func new(relay: String) -> PhonePairing {
        let ch = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        return PhonePairing(relay: relay, channel: ch, key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    /// What the QR code holds.
    public var code: String { "notchi-pair:" + ((try? JSONEncoder().encode(self)) ?? Data()).base64EncodedString() }
    public static func from(code: String) -> PhonePairing? {
        guard code.hasPrefix("notchi-pair:"), let d = Data(base64Encoded: String(code.dropFirst(12))),
              let p = try? JSONDecoder().decode(PhonePairing.self, from: d), p.key.count == 32,
              p.channel.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { return nil }
        return p
    }

    public func seal<T: Encodable>(_ value: T) throws -> String {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .millisecondsSince1970
        return try AES.GCM.seal(enc.encode(value), using: SymmetricKey(data: key)).combined!.base64EncodedString()
    }
    public func open<T: Decodable>(_ type: T.Type, _ box: String) -> T? {
        guard let d = Data(base64Encoded: box), let s = try? AES.GCM.SealedBox(combined: d),
              let plain = try? AES.GCM.open(s, using: SymmetricKey(data: key)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .millisecondsSince1970
        return try? dec.decode(type, from: plain)
    }
}

public enum PhoneRules {
    /// The phone may answer only an ordinary request that is still waiting; risky ones need a click on the Mac.
    public static func accept(_ a: PhoneAnswer, waiting: [PhoneApproval], now: Date) -> PhoneApproval? {
        guard let r = waiting.first(where: { $0.id == a.id }), !r.risky, now.timeIntervalSince(a.at) < 120 else { return nil }
        return r
    }
    /// The Watch ring: how far through a run (fills over 30 minutes).
    public static func ring(startedAt: Date?, now: Date) -> Double { startedAt.map { min(1, max(0, now.timeIntervalSince($0) / 1800)) } ?? 0 }
}
