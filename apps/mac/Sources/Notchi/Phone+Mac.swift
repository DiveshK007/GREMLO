import AppKit
import CoreImage.CIFilterBuiltins
import CryptoKit
import NotchiCore

// Phone and Watch (base §10, R4 §17): the Mac seals its state for the paired phone and takes the phone's answers.
// The relay only sees sealed boxes. The phone may answer ordinary requests; risky ones say "Open on the Mac".

final class PhoneController {
    unowned let backend: Backend
    var lastSent = ""
    var lastBeat = Date.distantPast
    /// The pairing holds the key that seals approvals, so it lives in the Keychain (an older copy in defaults moves).
    var pairing: PhonePairing? {
        get {
            if let old = defaults.string(forKey: "phone.pairing") { Keychain.set(old); defaults.removeObject(forKey: "phone.pairing") }
            return Keychain.get().flatMap(PhonePairing.from(code:))
        }
        set { if let c = newValue?.code { Keychain.set(c) } else { Keychain.delete() } }
    }

    init(backend: Backend) {
        self.backend = backend
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    func state() -> PhoneState {
        let b = backend
        let waiting = b.broker.queue.waiting.prefix(4).map { PhoneApproval(id: $0.id, tool: $0.tool, summary: String($0.summary.prefix(120)), risky: $0.risky) }
        return PhoneState(name: b.growth.petDisplayName, species: b.pet.skin.name, mood: b.pet.mood,
                          running: b.run.started != nil && b.run.endedAt == nil, startedAt: b.run.started, tools: b.run.tools,
                          waiting: Array(waiting), quiet: silence.silent, doneAt: b.run.endedAt, at: Date())
    }

    private func tick() {
        guard let p = pairing else { return }
        var s = state()
        let key = "\(s.mood)|\(s.running)|\(s.tools)|\(s.waiting.map(\.id))|\(s.quiet)|\(s.doneAt?.timeIntervalSince1970 ?? 0)"
        // the state changes rarely; send on a change, and every 30 s so the phone knows the Mac is there
        if key != lastSent || Date().timeIntervalSince(lastBeat) >= 30 {
            s.at = Date()
            lastBeat = s.at
            if let box = try? p.seal(s) { put("/phone/\(p.channel)/state", p.relay, ["box": box]) }
            lastSent = key
        }
        get("/phone/\(p.channel)/answers", p.relay) { [weak self] data in
            guard let self, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let boxes = o["boxes"] as? [String] else { return }
            for b in boxes {
                guard let a = p.open(PhoneAnswer.self, b), let r = PhoneRules.accept(a, waiting: self.state().waiting, now: Date()) else { continue }
                self.backend.broker.answer(r.id, a.allow ? .allowOnce : .deny)
                print("approval: answered from the phone")
            }
        }
    }

    private func put(_ path: String, _ relay: String, _ body: [String: Any]) {
        guard let url = URL(string: relay + path) else { return }
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.httpMethod = "PUT"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r).resume()
    }
    private func get(_ path: String, _ relay: String, done: @escaping (Data) -> Void) {
        guard let url = URL(string: relay + path) else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 10)) { d, resp, _ in
            guard let d, (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { done(d) }
        }.resume()
    }

    static func qr(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let ci = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)) else { return nil }
        let rep = NSCIImageRep(ciImage: ci)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        return img
    }
}

extension Backend {
    func phoneControls() -> [NSView] {
        var v: [NSView] = [caption("Phone and Watch (approvals are sealed; the relay can't read them)")]
        if let p = phone.pairing {
            if let img = PhoneController.qr(p.code) {
                let iv = NSImageView(image: img)
                iv.widthAnchor.constraint(equalToConstant: 180).isActive = true
                iv.heightAnchor.constraint(equalToConstant: 180).isActive = true
                v.append(iv)
            }
            v.append(label("Scan in the Notchi phone app, or copy the code.", 11, .regular, .secondaryLabelColor))
            v.append(NSStackView(views: [NSButton(title: "Copy pairing code", target: self, action: #selector(copyPairing)),
                                         NSButton(title: "Unpair", target: self, action: #selector(unpairPhone))]))
        } else {
            v.append(NSButton(title: "Pair a phone", target: self, action: #selector(pairPhone)))
        }
        return v
    }
    @objc func pairPhone() { phone.pairing = PhonePairing.new(relay: base); showingSettings = false; openSettings() }
    @objc func unpairPhone() { phone.pairing = nil; showingSettings = false; openSettings() }
    @objc func copyPairing() {
        guard let p = phone.pairing else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(p.code, forType: .string)
    }
}

// MARK: - Settings, Advanced: the only place account ids and hashes show (R4 §18, R2 §16)

extension Backend {
    func advancedControls() -> [NSView] {
        var v: [NSView] = [caption("Advanced")]
        v.append(row("Pet account", petName))
        v.append(row("Server", base))
        let sha = { (u: URL?) -> String in
            guard let u, let d = try? Data(contentsOf: u) else { return "\u{2014}" }
            return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined().prefix(16) + "\u{2026}"
        }
        let bundled = Bundle.main.url(forResource: "notchi-hook", withExtension: "sh") ?? Bundle.module.url(forResource: "notchi-hook", withExtension: "sh")
        let running = sha(ClaudeHooks.scriptURL), shipped = sha(bundled)
        v.append(row("Running hook", running))
        v.append(row("This build's hook", shipped))
        if running != shipped && running != "\u{2014}" { v.append(label("The installed hook differs from this build's; it's replaced at the next launch.", 11, .regular, .systemOrange)) }
        if info?.explorer != nil { v.append(NSButton(title: "Open the pet's account in the explorer", target: self, action: #selector(openAccount))) }
        return v
    }
    @objc func openAccount() {
        guard let e = info?.explorer, let u = URL(string: "\(e)/address/\(petName)") else { return }
        NSWorkspace.shared.open(u)
    }
}

/// One generic-password item for the phone pairing.
enum Keychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.notchi.phone", kSecAttrAccount as String: "pairing"]
    static func get() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ v: String) {
        delete()
        var q = query; q[kSecValueData as String] = Data(v.utf8); q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}
