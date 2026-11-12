import AppKit
import NotchiCore

// R2 §10: the local socket the CLI, Shortcuts and Raycast talk to, and the notchi:// URL scheme. Requests are
// parsed and limited in NotchiCore/Commands.swift; nothing here can spend, pay, change the payout address or allow
// a risky command.

extension Backend {
    /// Every CLI, URL, Shortcuts and Raycast request lands here (on the main thread).
    func handle(_ r: Request) -> Reply {
        guard Commands.known.contains(r.cmd) else { return Reply(ok: false, text: "unknown command") }
        switch r.cmd {
        case "status":
            let g = growth.p
            let earner = growth.isEgg ? "egg" : paused ? "paused" : privacy.focus != nil ? "focus" : pet.plate != nil ? "holding the line" : "not holding a line"
            let d: [String: String] = ["pet": growth.petDisplayName, "species": pet.skin.name, "stage": growth.isEgg ? "egg" : "\(g.stage)",
                                       "mood": pet.mood, "earner": earner, "agents": "\((pet.sessionLive ? 1 : 0) + companions.pets.count)",
                                       "approvals": "\(broker.queue.waiting.count)", "stars": "\(g.stars)", "meals": "\(g.meals.count)"]
            let text = "\(d["pet"]!) the \(Roster.species(pet.skin.name)?.kind ?? "pet") \u{00B7} \(d["stage"]!) \u{00B7} \(d["mood"]!) \u{00B7} \(earner) \u{00B7} \(d["agents"]!) agent(s) \u{00B7} \(d["approvals"]!) waiting"
            return Reply(ok: true, text: text, data: d)
        case "say":
            guard let text = r.args["text"], !text.isEmpty, text.count <= Commands.sayMax else { return Reply(ok: false, text: "say: 1 to \(Commands.sayMax) characters") }
            guard sayLimiter.allow(now: Date(), screenShared: silence.screenShared) else { return Reply(ok: false, text: "say: once every 10 s, and not during a screen share") }
            pet.say(text, for: 5, you: true)
            return Reply(ok: true, text: "said")
        case "pause":
            pause(minutes: Double(r.args["min"].flatMap(Int.init) ?? 30))
            return Reply(ok: true, text: "paused for \(r.args["min"] ?? "30") min")
        case "resume":
            pausedUntil = .distantPast; shown = ""; render()
            return Reply(ok: true, text: "resumed")
        case "focus":
            guard let m = r.args["min"].flatMap(Int.init), FocusSession.durations.contains(m) else { return Reply(ok: false, text: "focus 25, 50 or 90") }
            if privacy.focus != nil { privacy.endFocus(finished: false) }
            privacy.toggleFocus(m)
            return Reply(ok: true, text: "focus for \(m) min; lines off")
        case "celebrate":
            guard pet.path == .floor else { pet.comeOut(then: .celebrate); return Reply(ok: true, text: "coming out to celebrate") }
            pet.set(.celebrate, then: .walk)
            return Reply(ok: true, text: "celebrated")
        case "trick":
            guard let t = r.args["name"].flatMap(Trick.init) else { return Reply(ok: false, text: "unknown trick") }
            guard growth.tricks.contains(t) else { return Reply(ok: false, text: "not learned yet: \(t.requirement)") }
            hunt.doTrick(t)
            return Reply(ok: true, text: t.rawValue)
        case "pet":
            guard let s = r.args["species"], Roster.species(s) != nil else { return Reply(ok: false, text: "unknown species") }
            if let why = growth.lockReason(s) { return Reply(ok: false, text: "\(s) unlocks with \(why)") }
            if let agent = r.args["agent"] {
                guard let (_, c) = companions.pets.first(where: { $0.key.hasPrefix(agent) }), let skin = loadSkin(id: s) else { return Reply(ok: false, text: "no running agent \(agent)") }
                c.setSkin(skin)
                return Reply(ok: true, text: "that agent's companion is now \(s)")
            }
            guard let skin = loadSkin(id: s) else { return Reply(ok: false, text: "can't load \(s)") }
            defaults.set(s, forKey: "skin")
            pet.setSkin(skin)
            shown = ""; render()
            return Reply(ok: true, text: "earner is now \(s)")
        case "approve":
            guard let top = broker.queue.top else { return Reply(ok: false, text: "nothing waiting") }
            let deny = r.args["answer"] == "deny"
            // a command can deny anything, but can only allow an ordinary request; risky ones need a click
            guard deny || ApprovalQueue.shortcutAllowed(top) else { return Reply(ok: false, text: "that one deletes, pushes or spends: answer it with a click") }
            broker.answer(top.id, deny ? .deny : .allowOnce)
            return Reply(ok: true, text: deny ? "denied" : "allowed once")
        case "hook":
            do {
                switch (r.args["action"], r.args["agent"]) {
                case ("install", "claude"): try ClaudeHooks.connect()
                case ("remove", "claude"): try ClaudeHooks.disconnect()
                case (let a?, "git"):
                    guard let script = Bundle.main.url(forResource: "notchi-git-hook", withExtension: "sh") ?? Bundle.module.url(forResource: "notchi-git-hook", withExtension: "sh") else { return Reply(ok: false, text: "git hook script missing") }
                    let global = r.args["global"] == "1"
                    if a == "install" { try global ? GitHooks.installGlobal(script: script) : GitHooks.install(repo: r.args["cwd"] ?? ".", script: script) }
                    else { try global ? GitHooks.removeGlobal() : GitHooks.remove(repo: r.args["cwd"] ?? ".") }
                default: return Reply(ok: false, text: "hook install|remove claude|git")
                }
            } catch { return Reply(ok: false, text: error.localizedDescription) }
            return Reply(ok: true, text: "done")
        case "log":
            let steps = todaysSteps()
            if r.args["json"] == "1" {
                let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
                return Reply(ok: true, text: String(decoding: (try? enc.encode(steps)) ?? Data(), as: UTF8.self))
            }
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            return Reply(ok: true, text: steps.map { "\(f.string(from: $0.start))  \($0.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \($0.tool)  \($0.summary)" }.joined(separator: "\n"))
        case "visit":
            return social.visit(r.args["to"] ?? "")
        case "preview":
            guard let dir = r.args["dir"] else { return Reply(ok: false, text: "preview <dir>") }
            let problems = PackCheck.problems(URL(fileURLWithPath: dir))
            guard problems.isEmpty, let skin = loadSkin(id: (dir as NSString).lastPathComponent, dir: URL(fileURLWithPath: dir)) else {
                return Reply(ok: false, text: problems.joined(separator: "\n"))
            }
            pet.setSkin(skin)  // not saved: the next launch or pick goes back to your species
            return Reply(ok: true, text: "previewing \(dir) until you pick a species")
        default: return Reply(ok: false, text: "unknown command")
        }
    }

    func todaysSteps() -> [Step] {
        let start = Calendar.current.startOfDay(for: Date())
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: RunLog.dir, includingPropertiesForKeys: nil)) ?? []
        let saved = files.compactMap { try? dec.decode([Step].self, from: Data(contentsOf: $0)) }.flatMap { $0 }
        return (saved + run.steps).filter { $0.start >= start }.sorted { $0.start < $1.start }
    }

    /// notchi://say?text=…, notchi://pause?min=30, notchi://focus?min=25.
    @objc func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s), let req = Commands.fromURL(url) else { return }
        let reply = handle(req)
        print("url: \(req.cmd) -> \(reply.text)")
    }

    /// Links `notchi` into a folder on PATH: /usr/local/bin if writable, else ~/.local/bin.
    @objc func installCommand() {
        let exe = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/notchi-cli")
        let dev = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("NotchiCLI")
        guard let src = [exe, dev].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            pet.say("The notchi command isn't built: run swift build in apps/mac", for: 5); return
        }
        let candidates = ["/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
        for dir in candidates {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            guard FileManager.default.isWritableFile(atPath: dir) else { continue }
            let link = (dir as NSString).appendingPathComponent("notchi")
            try? FileManager.default.removeItem(atPath: link)
            if (try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: src.path)) != nil {
                pet.say("Installed: \(link)", for: 5)
                print("cli: linked \(link)")
                return
            }
        }
        pet.say("Couldn't install the notchi command", for: 5)
    }
}
