import Foundation

// What the app, widgets and Watch share: the pairing and the last state opened from the relay (app group).
enum Store {
    #if os(watchOS)
    static let group = UserDefaults(suiteName: "group.dev.gremlo.watch") ?? .standard
    #else
    static let group = UserDefaults(suiteName: "group.dev.gremlo") ?? .standard
    #endif

    static var pairing: PhonePairing? {
        get { group.string(forKey: "pairing").flatMap(PhonePairing.from(code:)) }
        set { group.set(newValue?.code, forKey: "pairing") }
    }
    static var state: PhoneState? {
        get { group.data(forKey: "state").flatMap { try? decoder.decode(PhoneState.self, from: $0) } }
        set { group.set(newValue.flatMap { try? encoder.encode($0) }, forKey: "state") }
    }
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }()
}

/// Talks to the relay: reads the Mac's sealed state, posts sealed answers.
enum Relay {
    static func fetch(_ p: PhonePairing) async -> PhoneState? {
        guard let url = URL(string: "\(p.relay)/phone/\(p.channel)/state"),
              let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let box = o["box"] as? String else { return nil }
        return p.open(PhoneState.self, box)
    }

    static func answer(_ p: PhonePairing, id: String, allow: Bool) async -> Bool {
        guard let url = URL(string: "\(p.relay)/phone/\(p.channel)/answers"),
              let box = try? p.seal(PhoneAnswer(id: id, allow: allow, at: Date())) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["box": box])
        guard let (_, r) = try? await URLSession.shared.data(for: req) else { return false }
        return (r as? HTTPURLResponse)?.statusCode == 200
    }
}

/// The Mac hasn't sent anything for a minute: it's asleep, offline or the app is closed.
func isStale(_ s: PhoneState, now: Date = Date()) -> Bool { now.timeIntervalSince(s.at) > 60 }

/// After hours (23:00-06:00) the widgets show the pet asleep.
func afterHours(_ d: Date = Date()) -> Bool { let h = Calendar.current.component(.hour, from: d); return h >= 23 || h < 6 }
