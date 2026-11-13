import AppKit
import GremloCore

// R2 §11 team relay, R4 §12 guestbook visits, R4 §14 pet park, and R2 §15 "Not for me" / "Report".
// The earner never visits and no sponsored line ever appears on someone else's screen.

final class SocialController {
    unowned let backend: Backend
    var pendingVisits: [(from: String, species: String, pr: Int?, url: String?, at: Date)] = []
    var visitors: [Pet] = []
    var pet: Pet { backend.pet }

    static var team: String { defaults.string(forKey: "team.code") ?? "" }
    static var handle: String { defaults.string(forKey: "team.handle") ?? "" }
    static var parkOn: Bool { defaults.bool(forKey: "park") }
    static var blockedBrands: [String] { defaults.stringArray(forKey: "blockedBrands") ?? [] }

    init(backend: Backend) {
        self.backend = backend
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.poll() }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.parkHeartbeat() }
        parkHeartbeat()
    }

    private func poll() {
        if !Self.team.isEmpty && !Self.handle.isEmpty {
            let q = "team=\(enc(Self.team))&handle=\(enc(Self.handle))"
            backend.request("/relay/inbox?\(q)") { [weak self] data, _ in
                guard let self, let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = o["visits"] as? [[String: Any]] else { return }
                for v in list {
                    self.pendingVisits.append((v["from"] as? String ?? "a teammate", v["species"] as? String ?? "gremlo", v["pr"] as? Int, v["url"] as? String,
                                               Date(timeIntervalSince1970: (v["at"] as? Double ?? Date().timeIntervalSince1970 * 1000) / 1000)))
                }
            }
        }
        deliver()
        if PrivacyController.visitsOn, let id = defaults.string(forKey: "park.id"), let token = defaults.string(forKey: "park.token") {
            backend.request("/visits?id=\(id)&token=\(token)") { [weak self] data, _ in
                guard let self, let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = o["visits"] as? [[String: Any]] else { return }
                for v in list {
                    self.backend.privacy.visit(v)  // the guestbook entry always lands; the walk-in waits for a quiet screen
                    if !silence.silent && self.backend.privacy.duck == .none { self.walkIn(species: v["species"] as? String ?? "gremlo", plate: nil, url: nil, stay: GuestbookEntry.visitSeconds) }
                }
            }
        }
    }

    /// A teammate's companion waits through meetings, Focus and screen shares, and expires after 30 minutes.
    private func deliver() {
        pendingVisits.removeAll { Date().timeIntervalSince($0.at) > 1800 }
        guard !silence.silent, backend.privacy.focus == nil, let v = pendingVisits.first else { return }
        pendingVisits.removeFirst()
        let line = v.pr.map { "PR #\($0) \u{00B7} review?" } ?? "\(v.from) says hi"
        walkIn(species: v.species, plate: (line, "Visit from \(v.from)"), url: v.url, stay: 120)
        Feel.sound("door-open")
    }

    /// A visiting pet walks in from the screen edge, then goes home after `stay` seconds.
    private func walkIn(species: String, plate: (String, String)?, url: String?, stay: TimeInterval) {
        guard Roster.species(species) != nil, let skin = loadSkin(id: species) else { return }
        let door = Door(art: skin.doors, scale: skin.scale, accent: skin.accent)
        let v = Pet(skin: skin, door: door)
        v.isCompanion = true
        v.comeOut(then: .greet)
        if let (line, from) = plate {
            v.setSign(line, brand: from, sponsored: false)
            v.signLinks = url != nil
            v.onSignClick = { if let u = url.flatMap(URL.init(string:)), u.scheme == "https" { NSWorkspace.shared.open(u) } }
        }
        visitors.append(v)
        DispatchQueue.main.asyncAfter(deadline: .now() + stay) { [weak self, weak v] in
            guard let v else { return }
            v.setSign(nil)
            v.goHome(lock: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { v.retire(); self?.visitors.removeAll { $0 === v } }
        }
    }

    // MARK: Team

    func joinTeam(code: String, handle: String) {
        defaults.set(code, forKey: "team.code"); defaults.set(handle.lowercased(), forKey: "team.handle")
        guard !code.isEmpty, !handle.isEmpty else { return }
        backend.request("/relay/join", body: ["team": code, "handle": handle.lowercased()]) { [weak self] _, err in
            self?.pet.say(err == nil ? "Joined the team" : "Couldn't join: \(err!.prefix(60))", for: 4)
        }
    }

    /// Your companion (never the earner) goes to a teammate: "go say hi", or a PR review.
    func sendVisit(to: String, pr: String) {
        guard !Self.team.isEmpty, !Self.handle.isEmpty else { pet.say("Join a team in Settings first", for: 4); return }
        let species = Companions.species(earner: pet.skin.name, unlocked: backend.growth.p.unlocked, inUse: [])
        var body: [String: Any] = ["team": Self.team, "from": Self.handle, "to": to.lowercased(), "species": species]
        if let n = pr.split(separator: "/").last.flatMap({ Int($0) }) ?? Int(pr) { body["pr"] = n }
        if pr.hasPrefix("https://") { body["url"] = pr }
        backend.request("/relay/visit", body: body) { [weak self] _, err in
            self?.pet.say(err == nil ? "On its way to \(to)" : "Couldn't send: \(err!.prefix(60))", for: 4)
        }
    }

    // MARK: Park (opt-in; exactly name, species, stage and today's outfit)

    func setPark(_ on: Bool) {
        defaults.set(on, forKey: "park")
        if on { parkHeartbeat(); return }
        guard let id = defaults.string(forKey: "park.id"), let token = defaults.string(forKey: "park.token"),
              let url = URL(string: "\(backend.base)/park/\(id)?token=\(token)") else { return }
        var req = URLRequest(url: url); req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req).resume()
    }

    var parkPayload: [String: Any] {
        let g = backend.growth
        return ["name": g.petDisplayName, "species": pet.skin.name, "stage": g.isEgg ? "hatchling" : "\(g.p.stage)", "outfit": g.p.worn, "tricks": g.tricks.map(\.rawValue)]
    }

    private func parkHeartbeat() {
        guard Self.parkOn, !backend.growth.isEgg else { return }
        var body = parkPayload
        if let id = defaults.string(forKey: "park.id") { body["id"] = id; body["token"] = defaults.string(forKey: "park.token") ?? "" }
        backend.request("/park", body: body) { data, _ in
            guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = o["id"] as? String, let t = o["token"] as? String else { return }
            defaults.set(id, forKey: "park.id"); defaults.set(t, forKey: "park.token")
        }
    }

    /// gremlo://visit?to=<park id>: your pet's four park fields go to that pet's guestbook. Park members only.
    func visit(_ to: String) -> Reply {
        guard Self.parkOn else { return Reply(ok: false, text: "join the park first (Settings)") }
        backend.request("/visits", body: ["to": to, "from": parkPayload]) { _, _ in }
        return Reply(ok: true, text: "visiting")
    }

    // MARK: Not for me / Report

    func notForMe() {
        guard let brand = backend.campaign?.brand else { return }
        defaults.set(Array(Set(Self.blockedBrands + [brand])), forKey: "blockedBrands")
        backend.shown = ""; backend.render()
    }

    func report() {
        guard let c = backend.campaign else { return }
        backend.request("/lines/report", body: ["petKey": backend.petName, "campaignId": c.campaignId, "hook": backend.currentHook]) { [weak self] _, err in
            self?.pet.say(err == nil ? "Reported. Thanks." : "Couldn't report: \(err!.prefix(50))", for: 4)
        }
        notForMe()
    }

    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
}

extension Backend {
    /// Settings, Team and park. Both are opt-in; your companion visits, never the earner.
    func socialControls() -> [NSView] {
        let w = pageWidth
        let code = Field(SocialController.team, placeholder: "team code", width: 200)
        let handle = Field(SocialController.handle, placeholder: "your handle", width: 200)
        code.identifier = NSUserInterfaceItemIdentifier("team.code"); handle.identifier = NSUserInterfaceItemIdentifier("team.handle")
        teamFields = (code, handle)
        let to = Field("", placeholder: "teammate's handle", width: 200)
        let pr = Field("", placeholder: "https://github.com/\u{2026}/pull/1", width: 200)
        visitFields = (to, pr)
        return [
            UI.group("Team", [
                UI.row("Team code", "6 to 40 of a\u{2013}z, 0\u{2013}9 and dashes. Everyone on the team uses the same one.", code, width: w),
                UI.row("Your handle", nil, handle, width: w),
                UI.row("", nil, Btn("Join team", style: .primary, target: self, action: #selector(joinTeam)), width: w),
            ], note: "Opt-in on both sides. Your companion visits, never the earner.", width: w),
            UI.group("Send your companion", [
                UI.row("To", nil, to, width: w),
                UI.row("Pull request", "Optional.", pr, width: w),
                UI.row("", nil, Btn("Send", target: self, action: #selector(sendCompanion)), width: w),
            ], width: w),
            UI.group("Park", [
                UI.row("Show my pet in the park", "Name, species, stage and outfit only. No ranking, no counts.",
                       Toggle(on: SocialController.parkOn, target: self, action: #selector(togglePark(_:)), label: "Show my pet in the park"), width: w),
            ], width: w),
        ]
    }
    @objc func joinTeam() { if let (c, h) = teamFields { social.joinTeam(code: c.stringValue.trimmingCharacters(in: .whitespaces), handle: h.stringValue.trimmingCharacters(in: .whitespaces)) } }
    @objc func sendCompanion() { if let (to, pr) = visitFields { social.sendVisit(to: to.stringValue.trimmingCharacters(in: .whitespaces), pr: pr.stringValue.trimmingCharacters(in: .whitespaces)) } }
    @objc func togglePark(_ b: NSButton) { social.setPark(b.state == .on) }
    @objc func clearBlocked() { defaults.removeObject(forKey: "blockedBrands"); shown = ""; render(); settings.reload() }
    @objc func notForMe() { social.notForMe() }
    @objc func reportLine() { social.report() }
}
