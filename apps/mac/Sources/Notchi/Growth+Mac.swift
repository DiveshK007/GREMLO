import AppKit
import NotchiCore

// Growing up on the Mac (spec D §2, §6-8; R3 §3-4). Rules are in NotchiCore/Growth.swift. Everything here is local
// to this Mac: counts from hook events, meals from the server's settlement receipts, stars from the ledger.

final class GrowthController {
    private(set) var p: PetProgress
    private(set) var egg: Egg
    var day = DayCounts()
    private var dayKey = WaitClock.dayOf(Date())
    private var sessionStart: [String: Date] = [:]
    private var lastSessionEnd: Date?
    var unlockNote: (text: String, until: Date)?
    weak var pet: Pet?
    var onChange: (() -> Void)?

    static var diaryOn: Bool { defaults.bool(forKey: "diary") }  // opt-in, off by default
    static let diaryDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Notchi/diary")

    init(existingUser: Bool) {
        let dec = JSONDecoder()
        p = defaults.data(forKey: "growth").flatMap { Tolerant.decode(PetProgress.self, from: $0, defaults: PetProgress()) } ?? PetProgress()
        egg = defaults.data(forKey: "egg").flatMap { try? dec.decode(Egg.self, from: $0) } ?? Egg()
        if defaults.data(forKey: "growth") == nil && existingUser {
            // installed before hatching existed: the pet is already out, so it starts hatched (today, honestly dated)
            p.hatchedAt = Date(); p.firstAgent = "Claude Code"; egg.hatched = true
            p.stage = .hatchling
        }
        if p.unlocked.isEmpty { p.unlocked = Roster.all.filter(\.starter).map(\.id) }
        save()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.diaryTick() }
    }

    var isEgg: Bool { !egg.hatched }
    var stars: Int { p.stars }

    func save() {
        let enc = JSONEncoder()
        if let d = try? enc.encode(p) { defaults.set(d, forKey: "growth") }
        if let d = try? enc.encode(egg) { defaults.set(d, forKey: "egg") }
    }

    /// What the pet wears: what you chose, plus the elder's reading glasses when the face slot is free.
    var worn: [String] {
        var w = p.worn
        if p.stage == .elder && !w.contains(where: { Slot.of($0) == .face }) { w.append("glasses") }
        return Accessories.drawOrder(w)
    }

    // MARK: Hook events (counts only; never arguments, paths or prompts)

    func hook(_ h: [String: Any]) {
        let ev = h["hook_event_name"] as? String ?? ""
        let session = h["session_id"] as? String ?? ""
        let today = WaitClock.dayOf(Date())
        if today != dayKey { writeDiary(for: dayKey); dayKey = today; day = DayCounts() }
        switch ev {
        case "SessionStart":
            sessionStart[session] = Date()
            if isEgg, let pet, pet.path == .home { pet.comeOut(then: .hatch) }  // the egg arrives
        case "UserPromptSubmit": day.runs += 1
        case "PreToolUse":
            p.toolCalls += 1
            if let t = h["tool_name"] as? String { day.tools[t, default: 0] += 1 }
            if isEgg { eggEffect(egg.toolCall()) }
        case "Stop":
            Stars.celebrated(&p, at: Date())
            if isEgg, let fx = egg.stop() { eggEffect(fx) }
        case "StopFailure":
            p.failedRuns += 1; day.failures += 1
        case "SessionEnd":
            if let s = sessionStart.removeValue(forKey: session) { p.longestSession = max(p.longestSession, Date().timeIntervalSince(s)) }
            lastSessionEnd = Date()
        default: break
        }
        checkUnlocks()
        save()
    }

    func approvalAnswered() { Stars.approvalAnswered(&p, at: Date()); day.approvals += 1; checkUnlocks(); save(); onChange?() }
    func stomped() { p.stomps += 1; checkUnlocks(); save() }
    func sessionTools(_ n: Int) { if n > p.maxSessionTools { p.maxSessionTools = n; if n == 100 { save() } } }
    func focusFinished(id: String) { Stars.focusFinished(&p, id: id, at: Date()); save(); onChange?() }
    func addGuest(_ e: GuestbookEntry) { p.guestbook = Array((p.guestbook + [e]).suffix(200)); save(); onChange?() }
    func toggleFurniture(_ id: String) { Room.toggle(id, &p); save(); onChange?() }
    func takeFurniture(_ id: String) { if Room.take(id, &p, at: Date()) { Feel.haptic(.tick); save(); onChange?() } }
    func setBugJar(_ n: Int) { p.bugJar = n; save(); onChange?() }
    func releaseTag() { p.releaseTags += 1; save(); onChange?() }
    var tricks: [Trick] { Trick.learned(approvals: p.approvalsAnswered, maxSessionTools: p.maxSessionTools, releaseTags: p.releaseTags) }
    func mood(_ m: String) {
        guard m == "thriving" else { return }
        let d = WaitClock.dayOf(Date())
        if !p.thrivingDays.contains(d) { p.thrivingDays = Array((p.thrivingDays + [d]).suffix(60)); checkUnlocks(); save() }
    }

    /// Settlement receipts from the server. Each one is a meal, once. Seeded data never grows the pet.
    func meals(_ receipts: [String], seeded: Bool) {
        guard !seeded else { return }
        let before = p.stage, count = p.meals.count
        for r in receipts { Stars.meal(&p, receipt: r, at: Date()) }
        guard p.meals.count != count else { return }
        if p.stage != before, let pet { pet.set(.evolve, then: .walk); print("growth: \(before) -> \(p.stage)") }
        checkUnlocks(); save(); onChange?()
    }

    // MARK: Hatching

    func eggEffect(_ fx: Egg.Effect) {
        guard let pet else { return }
        switch fx {
        case .wobble(let f): pet.eggFrame = f
        case .crack(let f): pet.eggFrame = f; Feel.haptic(.tick)
        case .glow: pet.eggFrame = 5; Feel.haptic(.tick)
        case .hatch: hatch()
        }
        save(); onChange?()
    }

    func skip() { eggEffect(egg.skip()) }

    private func hatch() {
        guard let pet else { return }
        p.starter = p.starter ?? pet.skin.name
        p.hatchedAt = Date(); p.firstAgent = p.firstAgent ?? "Claude Code"
        p.stage = Stage.from(meals: p.meals.count, hatched: true, previous: p.stage)
        if !p.unlocked.contains(pet.skin.name) { p.unlocked.append(pet.skin.name) }
        Stars.earn(&p, "hatching day", Stars.hatchingDay, ref: "hatch", at: Date())
        pet.eggFrame = 6
        Feel.event("hatch")
        Feel.haptic(.hatch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pet.eggFrame = 7 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { pet.egg = false; pet.set(.celebrate, then: .walk) }
        print("growth: hatched \(pet.skin.name)")
        save()
    }

    // MARK: Unlocks

    private func checkUnlocks() {
        for id in Unlocks.earned(p) {
            p.unlocked.append(id)
            guard let s = Roster.species(id) else { continue }
            unlockNote = ("New egg: \(s.name) \u{00B7} \(s.unlock)", Date().addingTimeInterval(8))
            print("growth: unlocked \(id)")
            onChange?()
        }
    }

    func lockReason(_ id: String) -> String? {
        guard let s = Roster.species(id) else { return "unknown" }
        return p.unlocked.contains(id) ? nil : s.unlock
    }

    // MARK: Closet

    func take(_ item: String) { if Closet.take(item, &p, at: Date()) { Feel.haptic(.tick); _ = Closet.wear(item, &p); save(); onChange?() } }
    func wear(_ item: String) { if Closet.wear(item, &p) { Feel.haptic(.tick); save(); onChange?() } }
    func takeOff(_ item: String) { p.worn.removeAll { $0 == item }; save(); onChange?() }

    // MARK: Diary (opt-in): written once the day's sessions are over, from counts only

    private func diaryTick() {
        guard Self.diaryOn, sessionStart.isEmpty, let end = lastSessionEnd, Date().timeIntervalSince(end) > 1800 else { return }
        writeDiary(for: dayKey)
        lastSessionEnd = nil
    }

    private func writeDiary(for key: String) {
        guard Self.diaryOn, day.runs > 0 else { return }
        // shortcut: the template only; a model-written entry needs a paid call with a request ID (and its own opt-in)
        let text = Diary.template(day, name: petDisplayName) + "\n"
        try? FileManager.default.createDirectory(at: Self.diaryDir, withIntermediateDirectories: true)
        try? text.write(to: Self.diaryDir.appendingPathComponent("\(key).txt"), atomically: true, encoding: .utf8)
    }

    var lastDiary: String? {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.diaryDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let latest = files.filter { $0.pathExtension == "txt" }.max { ($0.lastPathComponent) < ($1.lastPathComponent) }
        return latest.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var petDisplayName: String { defaults.string(forKey: "petName") ?? p.name }

    var certificate: Certificate? {
        guard let at = p.hatchedAt, let pet else { return nil }
        let kind = Roster.species(p.starter ?? pet.skin.name)?.kind ?? "pet"
        return Certificate(name: petDisplayName, species: kind, hatchedAt: at, firstAgent: p.firstAgent ?? "Claude Code")
    }
}

// MARK: - Companions: one earner, a companion per other running agent (spec D §2)

final class CompanionController {
    private(set) var pets: [String: Pet] = [:]   // session id -> companion
    private var earnerSession: String?
    private var social = Social()
    private var rng = SeededRNG(seed: SeededRNG.daySeed(Date()))
    let earner: Pet
    let growth: GrowthController
    static let max = 3

    init(earner: Pet, growth: GrowthController) {
        self.earner = earner
        self.growth = growth
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.meetups() }
    }

    /// Returns true when a companion took the event, so the earner skips it.
    func route(_ hook: [String: Any]) -> Bool {
        let ev = hook["hook_event_name"] as? String ?? ""
        guard let session = hook["session_id"] as? String, !session.isEmpty else { return false }
        if earnerSession == nil || (!earner.sessionLive && pets[session] == nil && ev == "SessionStart") { earnerSession = session }
        if session == earnerSession {
            if ev == "SessionEnd" { earnerSession = nil }
            return false
        }
        if growth.isEgg { return false }  // no companions before the earner hatches
        var pet = pets[session]
        if pet == nil, ev != "SessionEnd", pets.count < Self.max { pet = spawn(session) }
        guard let pet else { return false }
        pet.handle(event: ev, notification: hook["notification_type"] as? String, tool: hook["tool_name"] as? String,
                   command: (hook["tool_input"] as? [String: Any])?["command"] as? String)
        if ev == "SessionEnd" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.retire(session) }
        }
        return true
    }

    private func spawn(_ session: String) -> Pet? {
        let id = Companions.species(earner: earner.skin.name, unlocked: growth.p.unlocked, inUse: pets.values.map(\.skin.name))
        guard let skin = loadSkin(id: id) else { return nil }
        let door = Door(art: skin.doors, scale: skin.scale, accent: skin.accent)
        let pet = Pet(skin: skin, door: door)
        pet.isCompanion = true
        pet.wornItems = []
        pets[session] = pet
        print("companion: \(id) for a new agent session")
        return pet
    }

    private func retire(_ session: String) {
        guard let pet = pets[session], pet.path == .home else { return }
        pets.removeValue(forKey: session)
        pet.retire()
        print("companion: \(pet.skin.name) went home for good")
    }

    /// Meetups between any two pets on the floor (R2 §5): wave, then maybe a high five, then maybe a chase.
    private func meetups() {
        let all = [earner] + Array(pets.values)
        guard all.count > 1 else { return }
        let quiet = earner.quiet
        for i in 0..<all.count { for j in (i + 1)..<all.count {
            let a = all[i], b = all[j]
            let free = { (p: Pet) in p.path == .floor && [.walk, .idle].contains(p.state) && !p.working && !p.waiting }
            guard let meet = social.meet((a.skin.name, a.pos.x, a.dir, free(a), false), (b.skin.name, b.pos.x, b.dir, free(b), false),
                                         now: Date(), quiet: quiet, rng: &rng) else { continue }
            for p in [a, b] { p.set(.greet, then: meet.contains(.chase) ? .walk : .idle) }
            if meet.contains(.highFive) { Feel.sound("high-five") }
            if meet.contains(.chase) { b.dir = a.dir }
        } }
    }
}

// MARK: - The growth window: stage, stars ledger, Closet, certificate, diary

extension Backend {
    @objc func openGrowth() {
        growthWindow.title = "\(growth.petDisplayName)"
        rebuildGrowth()
        growthWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        growthWindow.makeKeyAndOrderFront(nil)
    }

    func rebuildGrowth() {
        guard growthWindow.isVisible || growthStack.arrangedSubviews.isEmpty else { return }
        let s = growthStack
        s.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let p = growth.p
        let stage = growth.isEgg ? "Egg (\(growth.egg.calls) of 50 tool calls)" : "\(p.stage)".capitalized
        s.addArrangedSubview(label(stage, 20, .semibold))
        s.addArrangedSubview(label("\(p.meals.count) meals \u{00B7} \(p.stars) stars", 13, .regular, .secondaryLabelColor))
        if p.stage < .elder && !growth.isEgg {
            let next = p.stage == .hatchling ? 10 : 50
            s.addArrangedSubview(bar(CGFloat(p.meals.count) / CGFloat(next)))
            s.addArrangedSubview(label("\(next - p.meals.count) meals to \(p.stage == .hatchling ? "Buddy" : "Elder"). Each meal is a real receipt.", 11, .regular, .tertiaryLabelColor))
        }
        if growth.isEgg {
            let b = NSButton(title: "Hatch now", target: self, action: #selector(hatchNow))
            s.addArrangedSubview(b)
        }

        s.addArrangedSubview(label("Bug jar: \(p.bugJar) caught on passing runs", 12, .regular, .secondaryLabelColor))
        s.addArrangedSubview(caption("Tricks (learned, never sold)"))
        for t in Trick.allCases {
            if growth.tricks.contains(t) {
                let b = ItemButton(title: t.rawValue.capitalized, target: self, action: #selector(doTrick(_:)))
                b.item = t.rawValue
                s.addArrangedSubview(b)
            } else {
                s.addArrangedSubview(label("\(t.rawValue.capitalized): learned at \(t.requirement)", 11, .regular, .tertiaryLabelColor))
            }
        }

        s.addArrangedSubview(caption("Closet (stars are earned, never bought)"))
        let names = pet.skin.pack.notchi.accessories?.names ?? []
        for item in names {
            let state: String
            var action: (String, Selector)?
            switch Closet.availability(item, p) {
            case .owned:
                let on = p.worn.contains(item)
                state = on ? "wearing" : "yours"
                action = on ? ("Take off", #selector(closetTakeOff(_:))) : ("Wear", #selector(closetWear(_:)))
            case .buy(let n):
                state = n == 0 ? "earned" : "\(n) stars"
                action = ("Take", #selector(closetTake(_:)))
            case .needStars(let have, let need): state = "\(have) of \(need) stars"
            case .milestone(let m, let progress): state = "\(m) (\(progress))"
            }
            let try_ = ItemButton(title: "Try on", target: self, action: #selector(closetTry(_:)))
            try_.item = item
            var views: [NSView] = [label(item, 12, .medium), label(state, 11, .regular, .secondaryLabelColor), NSView(), try_]
            if let action { let b = ItemButton(title: action.0, target: self, action: action.1); b.item = item; views.append(b) }
            let r = NSStackView(views: views)
            r.widthAnchor.constraint(equalToConstant: 320).isActive = true
            s.addArrangedSubview(r)
        }

        s.addArrangedSubview(caption("Room (same stars; pull the notch down to see it)"))
        for f in Room.items {
            let owned = p.furniture.contains(f.id)
            var views: [NSView] = [label(f.id, 12, .medium), label(owned ? (p.placed.contains(f.id) ? "in the room" : "put away") : "\(f.stars) stars", 11, .regular, .secondaryLabelColor), NSView()]
            if !owned && p.stars >= f.stars { let b = ItemButton(title: "Take", target: self, action: #selector(roomTake(_:))); b.item = f.id; views.append(b) }
            let r = NSStackView(views: views)
            r.widthAnchor.constraint(equalToConstant: 320).isActive = true
            s.addArrangedSubview(r)
        }
        s.addArrangedSubview(NSButton(title: "Open the room", target: self, action: #selector(openRoom)))

        s.addArrangedSubview(caption("Guestbook"))
        if p.guestbook.isEmpty { s.addArrangedSubview(label(PrivacyController.visitsOn ? "no visits yet" : "visits are off (Settings)", 11, .regular, .secondaryLabelColor)) }
        let gf = DateFormatter(); gf.dateStyle = .short; gf.timeStyle = .short
        for e in p.guestbook.suffix(5).reversed() {
            let kind = Roster.species(e.species)?.name ?? e.species
            s.addArrangedSubview(label("\(e.pet), a \(e.stage) \(kind)\(e.outfit.isEmpty ? "" : " in " + e.outfit.joined(separator: ", ")) \u{00B7} \(gf.string(from: e.at))", 11, .regular, .secondaryLabelColor))
        }

        s.addArrangedSubview(caption("Weekly postcard (Sundays 18:00; saved here, never posted)"))
        if let pc = privacy.latestPostcard, let img = NSImage(contentsOf: pc) {
            let iv = NSImageView(image: img)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.widthAnchor.constraint(equalToConstant: 320).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 160).isActive = true
            s.addArrangedSubview(iv)
            s.addArrangedSubview(NSStackView(views: [NSButton(title: "Save\u{2026}", target: self, action: #selector(savePostcard)), NSButton(title: "Copy", target: self, action: #selector(copyPostcard))]))
        }
        s.addArrangedSubview(NSButton(title: "Make this week's postcard now", target: self, action: #selector(makePostcardNow)))

        s.addArrangedSubview(caption("Stars ledger"))
        if p.ledger.isEmpty { s.addArrangedSubview(label("nothing yet", 11, .regular, .secondaryLabelColor)) }
        for row in p.ledger.suffix(6).reversed() {
            s.addArrangedSubview(label("\(row.amount > 0 ? "+" : "")\(row.amount)  \(row.reason)", 11, .regular, .secondaryLabelColor, mono: true))
        }

        if let c = growth.certificate {
            s.addArrangedSubview(caption("Certificate (private until you share it)"))
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
            for l in c.lines(dateFormat: { df.string(from: $0) }) { s.addArrangedSubview(label(l, 12, .regular)) }
            s.addArrangedSubview(NSButton(title: "Copy certificate", target: self, action: #selector(copyCertificate)))
        }

        s.addArrangedSubview(caption("Diary"))
        let diary = NSButton(checkboxWithTitle: "Write a diary entry after the day's last session (counts only, stays on this Mac)", target: self, action: #selector(toggleDiary(_:)))
        diary.state = GrowthController.diaryOn ? .on : .off
        s.addArrangedSubview(diary)
        if let d = growth.lastDiary { s.addArrangedSubview(label(d, 12, .regular)) }
    }

    @objc func hatchNow() { growth.skip(); rebuildGrowth() }
    @objc func doTrick(_ b: ItemButton) { if let t = Trick(rawValue: b.item) { hunt.doTrick(t) } }
    @objc func closetTake(_ b: ItemButton) { growth.take(b.item); applyWorn(); rebuildGrowth() }
    @objc func closetWear(_ b: ItemButton) { growth.wear(b.item); applyWorn(); rebuildGrowth() }
    @objc func closetTakeOff(_ b: ItemButton) { growth.takeOff(b.item); applyWorn(); rebuildGrowth() }
    /// Free and unlimited; reverts after 10 s.
    @objc func closetTry(_ b: ItemButton) {
        let item = b.item
        pet.wornOverride = Accessories.drawOrder(growth.worn.filter { Slot.of($0) != Slot.of(item) } + [item])
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.pet.wornOverride?.contains(item) == true { self?.pet.wornOverride = nil }
        }
    }
    @objc func copyCertificate() {
        guard let c = growth.certificate else { return }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(c.lines(dateFormat: { df.string(from: $0) }).joined(separator: "\n"), forType: .string)
    }
    @objc func toggleDiary(_ b: NSButton) { defaults.set(b.state == .on, forKey: "diary") }

    func applyWorn() { pet.wornItems = growth.worn }
}

final class ItemButton: NSButton { var item = "" }
