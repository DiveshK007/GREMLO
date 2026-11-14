import GremloCore
import AppKit
import CryptoKit
import Network
import UserNotifications

// The app's link to apps/server and the menu bar panel (moved out of main.swift unchanged).

// Talks to apps/server. Server down means the popover says so; nothing is invented.
final class Backend: NSObject {
    let base = Legacy.env("SERVER") ?? "http://localhost:8787"
    let petName = startupPetName()
    let pet: Pet
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = MenuPanel()
    lazy var settings: SettingsWindow = { let s = SettingsWindow(); s.build = { [unowned self] in self.settingsPage($0) }; return s }()
    let stack = NSStackView()
    var campaign: Campaign?
    var info: PetInfo?
    var lastThink = "no think yet"
    var serverError: String?
    var thinking = false
    var lastImpression: [String: Date] = [:] // campaign id -> last report; server enforces the same window
    var waited = WaitClock()
    // Hook rotation: the next hook on each new appearance of the sign, and every 45s while it stays up.
    var hookIndex = 0
    var hookSince = Date()
    var signWasUp = false
    // follows the server's auto-optimised order when there is one, plain round robin otherwise
    /// The line for this slot of the A/B rotation, preferring lines tagged for what the agent is doing now.
    var currentHook: Int { pickedHook ?? 0 }
    var pickedHook: Int? {
        guard let c = campaign, !c.allHooks.isEmpty else { return nil }
        let base = c.order?.isEmpty == false ? c.order! : Array(0..<c.allHooks.count)
        let order = base.filter { $0 >= 0 && $0 < c.allHooks.count && !(c.paused ?? []).contains($0) }
        let live = run.started != nil && run.endedAt == nil
        let moment = LineMoment.current(command: run.steps.last?.command, runSeconds: live ? run.elapsed : 0, extraRunners: HuntController.extraRunners)
        return LineMoment.pick(order: order, tags: c.moments ?? [], moment: moment, slot: hookIndex)
    }
    var currentMoment: String {
        LineMoment.current(command: run.steps.last?.command, runSeconds: run.started != nil && run.endedAt == nil ? run.elapsed : 0, extraRunners: HuntController.extraRunners)
    }
    // Polls overlap (timer + after each think); a late reply must not roll the balance back and re-show a meal.
    var petSent = 0, petApplied = 0
    // Rebuild the panel only when what it shows changes, so a "copied" click survives the 10s polls.
    var shown = ""
    private var iconSkin = ""
    // Demo mode: lets you trigger every pet reaction from the menu bar for a demo. Local only: while it is on,
    // no AI think calls and no views are reported, so nothing is spent or paid. Demo content is labelled [demo].
    var demoMode = false
    // Notch Live: approvals answered on a surface, the current run, the panel (NotchLive+Mac.swift)
    let broker = ApprovalBroker()
    let run = RunTracker()
    lazy var live: NotchLiveController = { let l = NotchLiveController(broker: broker, run: run); l.backend = self; return l }()
    var pausedUntil = Date.distantPast
    var paused: Bool { Date() < pausedUntil }
    /// Long press on the notch: pets home, lines off, counters frozen, for `minutes` (spec R3 §2).
    func pause(minutes: Double) {
        pausedUntil = Date().addingTimeInterval(minutes * 60)
        pet.goHome(lock: false)
        print("paused for \(Int(minutes)) min")
        shown = ""; render()
    }
    // Growing up and companions (Growth+Mac.swift)
    let growth = GrowthController(existingUser: ClaudeHooks.isConnected)
    lazy var hunt: HuntController = HuntController(backend: self)
    lazy var privacy: PrivacyController = PrivacyController(backend: self)
    lazy var social: SocialController = SocialController(backend: self)
    lazy var phone: PhoneController = PhoneController(backend: self)
    lazy var purse: PurseController = PurseController(backend: self)
    lazy var github: GitHubController = GitHubController(backend: self)
    var teamFields: (NSTextField, NSTextField)?
    var visitFields: (NSTextField, NSTextField)?
    lazy var commandSocket: CommandSocket = CommandSocket { [unowned self] in self.handle($0) }
    var sayLimiter = SayLimiter()
    lazy var companions: CompanionController = CompanionController(earner: self.pet, growth: self.growth)
    lazy var growthStack: NSStackView = {
        let s = NSStackView(); s.orientation = .vertical; s.alignment = .leading; s.spacing = 6
        s.edgeInsets = NSEdgeInsets(top: UI.margin, left: UI.margin, bottom: UI.margin, right: UI.margin); return s
    }()
    lazy var growthWindow: NSWindow = {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        growthStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = growthStack
        growthStack.widthAnchor.constraint(equalToConstant: 380).isActive = true
        w.contentView = scroll
        w.isReleasedWhenClosed = false
        return w
    }()
    var demoHooks: [String]?
    var showingDemo = false
    let demoEvents: [(String, String)] = [
        ("Session starts (pet wakes behind the door)", "SessionStart"),
        ("You send a prompt (door opens, pet drops out)", "UserPromptSubmit"),
        ("Agent working (walks with the sign)", "PreToolUse"),
        ("Show a sponsored hook (demo ad)", "demo.ad"),
        ("Needs your approval (flag + jump)", "PermissionRequest"),
        ("Waiting for your input (taps foot)", "idle"),
        ("Agent done (celebrates)", "Stop"),
        ("Agent failed (trips, sad)", "StopFailure"),
        ("Session ends (goes home, door locks)", "SessionEnd"),
        ("Gets paid: compute budget refills", "demo.eat"),
        ("AI says something (bubble)", "demo.say"),
        ("Come-back reminder notification", "demo.remind"),
        ("Mood: thriving", "mood.thriving"),
        ("Mood: hungry (compute budget empty)", "mood.hungry"),
        ("Mood: asleep (chain unreachable)", "mood.asleep"),
        ("Trick: backflip", "trick.backflip"),
        ("Trick: moonwalk", "trick.moonwalk"),
        ("Try on the next accessory", "demo.tryon"),
        ("Take accessories off", "demo.undress"),
    ]
    var demoPick = 0
    lazy var reminders: Reminders = Reminders(pet: self.pet)

    init(pet: Pet) {
        self.pet = pet
        super.init()
        run.onEnd = { RunLog.save($0) }  // the scrubber keeps each run for 7 days
        pet.onHome = { [weak self] in
            guard let self else { return }
            self.live.show(.home("\(self.growth.petDisplayName.capitalized) is home"))
            Feel.haptic(.boop)
        }
        pet.onContextChange = { [weak self] in self?.shown = ""; self?.render() }
        growth.pet = pet
        growth.askModel = { [weak self] payload, done in
            guard let self, !self.pet.offline, !self.demoMode else { done(nil, nil); return }
            self.request("/pets/\(self.petName)/diary", body: payload) { data, _ in
                let o = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if let p = o?["payFor"], let d = try? JSONSerialization.data(withJSONObject: p), let pay = try? JSONDecoder().decode(PayFor.self, from: d) { self.purse.pay(pay) }
                done(o?["entry"] as? String, o?["requestId"] as? String)
            }
        }
        pet.egg = growth.isEgg
        pet.eggFrame = growth.egg.restFrame
        pet.wornItems = growth.worn
        if pet.egg { pet.state = .hatch }
        pet.onEggSkip = { [weak self] in self?.growth.skip() }
        pet.onStomp = { [weak self] in self?.growth.stomped() }
        growth.onChange = { [weak self] in
            guard let self else { return }
            self.applyWorn(); self.rebuildGrowth(); self.shown = ""; self.render(); self.live.update()
        }
        broker.onAnswered = { [weak self] in self?.growth.approvalAnswered() }
        // A sign click goes through the server, which counts it once per window and redirects to the brand.
        pet.onSignClick = { [weak self] in
            guard let self, let c = self.campaign, c.url != nil else { return }
            let enc = { (v: String) in v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v }
            let path = "/c/\(c.campaignId)/\(self.currentHook)"
            var q = "pet=\(enc(self.petName))"
            // a browser can't send headers, so the click's signature rides in the query (over the pet name)
            if let s = deviceSign(method: "GET", path: path, body: Data(self.petName.utf8)) { q += "&key=\(s.key)&t=\(s.time)&sig=\(s.sig)" }
            if let u = URL(string: "\(self.base)\(path)?\(q)") { NSWorkspace.shared.open(u) }
        }
        UI.setAccent(pet.skin.species)
        statusIcon()
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.setAccessibilityLabel(productName)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UI.margin
        stack.edgeInsets = NSEdgeInsets(top: UI.margin, left: UI.margin, bottom: UI.margin, right: UI.margin)
        stack.widthAnchor.constraint(equalToConstant: popoverWidth).isActive = true
        menu.onClose = { [weak self] in self?.showingDemo = false }
        refresh()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reportImpression() }
    }

    // BUILD_GUIDE section 8: working state, sign visible 5s, once per campaign per minute.
    func rotateHooks() {
        let up = pet.signShownAt != nil
        if (signWasUp && !up) || (up && Date().timeIntervalSince(hookSince) > 45) {
            hookIndex += 1
            hookSince = Date()
            render()
        }
        if up && !signWasUp { hookSince = Date() }
        signWasUp = up
    }

    func reportImpression() {
        rotateHooks()
        if demoMode || paused || privacy.focus != nil || PrivacyController.streamOn { return } // demo views are never paid; a pause, focus or stream mode counts nothing
        guard let c = campaign, !c.allHooks.isEmpty, let since = pet.signShownAt, Date().timeIntervalSince(since) >= 5 else { return }
        if let last = lastImpression[c.campaignId], Date().timeIntervalSince(last) < 60 { return }
        // Viewability (README): unlocked screen, sign visible (placeSign), someone used the Mac in the last 5 minutes.
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if locked || idle > 300 { return }
        lastImpression[c.campaignId] = Date()
        let view: [String: Any] = ["petKey": petName, "campaignId": c.campaignId, "hook": currentHook, "moment": currentMoment,
                                   "shownMs": Int(Date().timeIntervalSince(since) * 1000), "unlocked": true, "visible": true, "idleS": Int(idle)]
        print("view: posting campaign \(c.campaignId) hook \(currentHook), sign up \(Int(Date().timeIntervalSince(since)))s")
        request("/impressions", body: ["impressions": [view]]) { data, err in
            if let err { print("view: not sent: \(err)") }
            else { print("view: server answered \(String(decoding: data ?? Data(), as: UTF8.self).prefix(120))") }
            self.refresh()
        }
    }

    @objc func toggle() {
        if menu.isVisible { menu.dismiss(); return }
        showingDemo = false
        shown = ""
        render()
        menu.fit(stack, under: item.button)
        menu.open()
    }
    /// The menu bar icon is the pet itself, a small idle frame.
    func statusIcon() {
        guard iconSkin != pet.skin.name else { return }
        iconSkin = pet.skin.name
        guard let f = (pet.skin.strips[.idle] ?? pet.skin.strips[.walk])?.frames.first else { item.button?.title = productName; return }
        item.button?.image = UI.pixelIcon(f, side: 18)
        item.button?.title = ""
    }
    func resizeMenu() { if menu.isVisible { menu.fit(stack, under: item.button) } }

    var petPath: String { "/pets/" + (petName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? petName) }

    func request(_ path: String, body: [String: Any]? = nil, done: @escaping (Data?, String?) -> Void) {
        var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: 30)
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
            req.httpBody = data
            // the server checks this for paired pets; unpaired pets are accepted unsigned until paired
            if let s = deviceSign(method: "POST", path: path, body: data) {
                req.setValue(s.key, forHTTPHeaderField: "X-Gremlo-Key")
                req.setValue(s.time, forHTTPHeaderField: "X-Gremlo-Time")
                req.setValue(s.sig, forHTTPHeaderField: "X-Gremlo-Sig")
            }
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let fail = err.map { $0.localizedDescription } ?? (code == 200 ? nil : "HTTP \(code) \(String(decoding: data ?? Data(), as: UTF8.self).prefix(120))")
            DispatchQueue.main.async { done(fail == nil ? data : nil, fail) }
        }.resume()
    }

    func refresh() {
        request("/campaigns/active") { data, err in
            self.serverError = err
            if err != nil { self.campaign = nil } // can't confirm the campaign, so don't hold its sign
            if let data { self.campaign = try? JSONDecoder().decode(Campaign?.self, from: data) }
            self.render()
        }
        petSent += 1
        let seq = petSent
        request(petPath) { data, err in
            guard seq > self.petApplied else { return }
            self.petApplied = seq
            if let err {
                // No balance means no mood: sleep and say why instead of showing the last known one.
                self.serverError = "pet \(self.petName): \(err)"
                self.info = nil
                // a 404 means the server answered but doesn't know this pet; only a network error is "can't reach"
                self.pet.setMood("asleep", reason: err.hasPrefix("HTTP 404") ? "\(self.petName) isn't registered yet: get your pet on the web app"
                    : err.hasPrefix("HTTP") ? "server error: \(err.prefix(60))" : "can't reach the \(productName) server")
            }
            if let data, let new = try? JSONDecoder().decode(PetInfo.self, from: data) {
                // it eats when a settlement refills its onchain compute budget (real tx), or when its payout grows
                if self.info?.seeded == new.seeded, let gain = nearGain(self.info?.computeBalance, new.computeBalance) {
                    self.pet.eat(gain + " food" + (new.seeded ? " [seeded]" : ""))
                } else if self.info?.seeded == new.seeded, let gain = nearGain(self.info?.walletBalance, new.walletBalance) {
                    self.pet.eat(gain + (new.seeded ? " [seeded]" : ""))
                }
                self.info = new
                self.growth.meals(new.meals ?? [], seeded: new.seeded)
                self.growth.mood(new.mood)
            }
            self.render()
        }
    }

    // One think in flight at a time; events during a pending call are skipped so a tool burst can't stack paid calls.
    func think(_ hook: [String: Any]) {
        guard !thinking, !demoMode, !pet.offline, !paused, !pet.egg else { return } // no AI spend while demoing, offline or paused
        thinking = true
        let body: [String: Any] = ["event": hook["hook_event_name"] ?? "", "sessionId": hook["session_id"] ?? "",
                                   "toolName": hook["tool_name"] ?? "", "notificationType": hook["notification_type"] ?? "",
                                   // cosmetic: lets the pet page draw the right species and stage; never money or mood
                                   "species": pet.skin.name, "stage": growth.isEgg ? "egg" : "\(growth.p.stage)"]
        request(petPath + "/think", body: body) { data, err in
            self.thinking = false
            if let err { self.lastThink = "think failed: \(err)" }
            else if let data, let r = try? JSONDecoder().decode(ThinkResult.self, from: data) {
                if let pay = r.payFor { self.purse.pay(pay) }  // a purse pet pays for this thought itself
                let id = r.requestId.map { "completion \($0)" } ?? "no AI call"
                self.lastThink = r.action == "sleep" ? "sleep: \(r.reason ?? "") (\(id))" : "\(r.action) \"\(r.say ?? "")\" (\(id))"
                // Exactly what the AI said, only when it said something. Never invent a line.
                if let say = r.say?.trimmingCharacters(in: .whitespacesAndNewlines), !say.isEmpty {
                    self.pet.say(say, for: 4)
                    let mood = r.action == "celebrate" ? "happy" : r.action == "sad" ? "grumpy" : "say"
                    Feel.voice(species: self.pet.skin.name, mood: mood, requestId: r.requestId)
                }
            }
            self.refresh()
        }
    }

    func render() {
        let seeded = info?.seeded ?? false
        let tag = seeded ? " [seeded]" : ""
        if let demo = demoHooks, !demo.isEmpty {
            pet.signLinks = false
            pet.setSign(demo[hookIndex % demo.count] + " [demo]", brand: "Clearlog [demo]")
        } else {
            let hooks = campaign?.allHooks ?? []
            pet.signLinks = showHooks && campaign?.url != nil
            let blocked = campaign.map { SocialController.blockedBrands.contains($0.brand) } ?? false  // "Not for me"
            let line = showHooks && !hooks.isEmpty && pickedHook != nil && !blocked ? hooks[currentHook] + tag : nil
            pet.setSign(privacy.lineAllowed(line) ? line : nil, brand: campaign?.brand ?? "")  // focus, stream, share, 12/hour
        }
        if (paused || pet.egg) && !demoMode {
            pet.setSign(nil)  // paused, or still an egg: no line
        } else if pet.offline && !demoMode {
            // offline: sleeps, no lines, no meals, and says why (spec R2 §6)
            pet.setSign(nil)
            pet.setMood("asleep", reason: offlineReason)
        } else if let i = info, !demoMode { pet.setMood(i.mood, reason: i.moodReason) }
        if showingDemo { return }
        let key = "\(privacy.focus.map { Int($0.remaining(Date()) / 60) } ?? -1)|\(PrivacyController.streamOn)|\(growth.p.meals.count)|\(growth.p.stars)|\(growth.isEgg)|\(String(describing: info))|\(String(describing: campaign))|\(serverError ?? "")|\(lastThink)|\(pet.waiting)|\(pet.skin.name)|\(demoMode)|\(hookIndex)|\(sponsoredOn)"
        if key == shown { return }
        shown = key
        UI.setAccent(pet.skin.species)
        statusIcon()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let w = popoverWidth - UI.margin * 2
        let gp = growth.p

        // the pet: who it is and how it feels
        let tile = UI.wrap(UI.padded(avatar(), 4, 6), fill: UI.control, radius: 12)
        let stage = growth.isEgg ? "egg" : "\(gp.stage)"
        let names = UI.vstack([UI.label(info?.name ?? petName, UI.display(26), UI.fg, wrap: false),
                               UI.caption("\(info?.mood ?? "\u{2014}") \u{00B7} \(stage)", UI.accentText)], spacing: 4)
        let demoB = Btn(demoMode ? "Demo mode is on" : "Demo", style: .icon, symbol: demoMode ? "play.circle.fill" : "play.circle", target: self, action: #selector(openDemo))
        if demoMode { demoB.tint = .systemRed }
        let gear = Btn("Settings", style: .icon, symbol: "gearshape", target: self, action: #selector(openSettings))
        let head = UI.hstack([tile, names, UI.spacer(), demoB, gear], spacing: 12)
        head.widthAnchor.constraint(equalToConstant: w).isActive = true
        stack.addArrangedSubview(head)

        // what needs saying first
        var notes: [NSView] = []
        if seeded { notes.append(UI.notice("Seeded data, not real money", UI.amber, width: w)) }
        if let e = serverError { notes.append(UI.notice("Server: \(e)", UI.text3, width: w)) }
        // views count only from a paired Mac, so an unpaired one says so first and offers the one step that fixes it
        if info?.paired == false && !seeded {
            let pair = Btn("Pair", style: .primary, target: self, action: #selector(pairDevice)); pair.small = true
            let text = devicePublicKey == nil ? "This Mac has no Secure Enclave, so its views can't count." : "Not paired yet: views from this Mac don't count."
            let r = UI.hstack([UI.notice(text, UI.amber, width: w - (devicePublicKey == nil ? 0 : 64)), UI.spacer()] + (devicePublicKey == nil ? [] : [pair]))
            r.widthAnchor.constraint(equalToConstant: w).isActive = true
            notes.append(r)
        }
        if let f = privacy.focus {
            let end = Btn("End", style: .secondary, target: self, action: #selector(endFocusNow)); end.small = true
            let r = UI.hstack([UI.notice("Focus: \(Int(f.remaining(Date()) / 60) + 1) min left. Lines off, not earning.", UI.accent, width: w - 60), UI.spacer(), end])
            r.widthAnchor.constraint(equalToConstant: w).isActive = true
            notes.append(r)
        }
        if PrivacyController.streamOn { notes.append(UI.notice("Stream mode: lines off, views not counted", UI.text3, width: w)) }
        if let i = info, i.mood == "asleep" || i.mood == "hungry", let why = i.moodReason ?? (i.mood == "asleep" ? brokeReason : nil) {
            notes.append(UI.notice(why, i.mood == "hungry" ? UI.amber : UI.text3, width: w))
        }
        if !notes.isEmpty { stack.addArrangedSubview(column(notes, width: w)) }
        if pet.waiting {
            let b = Btn("Approve in terminal", style: .primary, symbol: "terminal", target: self, action: #selector(approveInTerminal))
            b.keyEquivalent = "\r"
            UI.fixed(b, w: w, h: 34)
            stack.addArrangedSubview(b)
        }

        // money: the two balances, side by side; the bars compare them to each other (there is no fixed "full")
        let earned = info?.walletBalance.flatMap { Decimal(string: $0) }
        let food = info?.computeBalance.flatMap { Decimal(string: $0) }
        let top = max(earned ?? 0, food ?? 0)
        let frac = { (v: Decimal?) -> CGFloat? in v.flatMap { top > 0 ? CGFloat(truncating: ($0 / top) as NSDecimalNumber) : nil } }
        let half = (w - 8) / 2
        stack.addArrangedSubview(UI.hstack([UI.stat("Earned" + (seeded ? " \u{00B7} seeded" : ""), near4(info?.walletBalance), fraction: frac(earned), width: half),
                                            UI.stat("Compute budget", near4(info?.computeBalance), fraction: frac(food), width: half)], spacing: 8, align: .top))
        var facts = [UI.kv("Today", "waited \(waited.minutes()) min \u{00B7} \(info.map { "\($0.impressionsToday)" } ?? "\u{2014}") views" + tag, width: w)]
        if let i = info, let views = i.paidViews { facts.append(UI.kv("Paid by brands", "\(near4(i.earnedWei)) for \(views) views" + tag, width: w)) }
        facts.append(UI.kv(growth.isEgg ? "Egg" : stage.capitalized, growth.isEgg ? "\(growth.egg.calls) of 50 tool calls" : "\(gp.meals.count) meals \u{00B7} \(gp.stars) \u{2605}", width: w))
        stack.addArrangedSubview(UI.group(nil, facts, width: w))

        // the line it holds right now, drawn as the plate with its AD tab
        let off = !sponsoredOn ? "Sponsored lines are off" : inQuietHours() ? "Quiet hours: no lines until 08:00"
            : (info?.impressionsToday ?? 0) >= dailyViewCap ? "Daily limit reached: no more lines today" : campaign == nil ? "No active campaign" : nil
        var showing: [NSView] = [UI.caption("Now showing")]
        if let off { showing.append(UI.label(off, UI.body(13), UI.text2, width: w)) }
        else if let c = campaign {
            showing.append(UI.plate(c.allHooks.isEmpty ? "\u{2014}" : c.allHooks[currentHook], width: w))
            let notMe = Btn("Not for me", style: .ghost, target: self, action: #selector(notForMe)); notMe.small = true
            let report = Btn("Report", style: .ghost, target: self, action: #selector(reportLine)); report.small = true
            let r = UI.hstack([UI.label("by \(c.brand)\(tag)", UI.body(11), UI.text2, wrap: false), UI.spacer(), notMe, report], spacing: 4)
            r.widthAnchor.constraint(equalToConstant: w).isActive = true
            showing.append(r)
        }
        stack.addArrangedSubview(column(showing, width: w))

        // its last paid thoughts, each with the completion id (click copies it)
        var thoughts: [NSView] = [UI.caption("Last thoughts")]
        let last = info?.lastThoughts.prefix(3) ?? []
        if last.isEmpty { thoughts.append(UI.label("None yet", UI.body(12), UI.text3)) }
        else { thoughts.append(UI.group(nil, last.map { copyButton($0.action.uppercased(), $0.requestId) }, width: w)) }
        if let tx = info?.lastThoughts.first(where: { $0.chargeTx != nil })?.chargeTx {
            let b = Btn("Receipt for the last AI charge", style: .ghost, symbol: "arrow.up.right", target: self, action: #selector(openLastCharge))
            b.small = true
            b.identifier = NSUserInterfaceItemIdentifier(tx)
            thoughts.append(b)
        }
        stack.addArrangedSubview(column(thoughts, width: w))

        stack.addArrangedSubview(UI.group(nil, [LinkRow("Closet, stars and certificate", width: w, target: self, action: #selector(openGrowth)),
                                                LinkRow("Pet page and weekly recap", width: w, target: self, action: #selector(openPetPage))], width: w))
        stack.addArrangedSubview(UI.label("Last think: \(lastThink)", UI.mono(10, .regular), UI.text3, width: w))
        // a menu-bar app has no app menu, so Quit lives here (and in Settings, General); Cmd+Q works while the panel is open
        let quit = Btn("Quit Gremlo", style: .ghost, symbol: "power", target: self, action: #selector(quitApp))
        quit.small = true
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        let foot = UI.hstack([UI.spacer(), UI.label("\u{2318}Q", UI.mono(10, .regular), UI.text3, wrap: false), quit], spacing: 6)
        foot.widthAnchor.constraint(equalToConstant: w).isActive = true
        stack.addArrangedSubview(foot)
        resizeMenu()
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    @objc func openSettings() { menu.dismiss(); settings.show() }

    @objc func openDemo() { showingDemo = true; renderDemo() }
    @objc func closeDemo() { showingDemo = false; shown = ""; render() }
    func renderDemo() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let w = popoverWidth - UI.margin * 2
        let back = Btn("Back", style: .icon, symbol: "chevron.left", target: self, action: #selector(closeDemo))
        let head = UI.hstack([back, UI.label("Demo", UI.display(26), UI.fg, wrap: false)], spacing: 8)
        head.widthAnchor.constraint(equalToConstant: w).isActive = true
        stack.addArrangedSubview(head)
        stack.addArrangedSubview(UI.label("Play any event to see what the pet does. Local only: while demo mode is on there are no AI calls and no paid views.", UI.body(12), UI.text2, width: w))
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItems(withTitles: demoEvents.map { $0.0 })
        picker.selectItem(at: demoPick)
        picker.target = self
        picker.action = #selector(pickDemo(_:))
        stack.addArrangedSubview(UI.group(nil, [
            UI.row("Demo mode", nil, Toggle(on: demoMode, target: self, action: #selector(toggleDemo(_:)), label: "Demo mode"), width: w),
            UI.vstack([UI.popup(picker)], insets: NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)),
        ], width: w))
        let play = Btn("Play", style: .primary, symbol: "play.fill", target: self, action: #selector(playDemo))
        play.keyEquivalent = "\r"
        UI.fixed(play, w: w, h: 34)
        stack.addArrangedSubview(play)
        resizeMenu()
    }
    @objc func pickDemo(_ sender: NSPopUpButton) { demoPick = sender.indexOfSelectedItem }
    @objc func toggleDemo(_ sender: NSButton) {
        demoMode = sender.state == .on
        if !demoMode { demoHooks = nil; shown = ""; refresh() } // back to real campaign and real mood
        render()
    }
    @objc func playDemo() {
        if !demoMode { demoMode = true; renderDemo() }
        let code = demoEvents[demoPick].1
        switch code {
        case "demo.ad":
            demoHooks = ["Clearlog: logs, found. Try it free", "Still grepping logs at 2am? Clearlog.", "Your hook here, carried by the pet"]
            pet.handle(event: "PreToolUse", notification: nil)
        case "idle": pet.handle(event: "Notification", notification: "idle_prompt")
        case "demo.eat": pet.eat("+0.0002 food [demo]")
        case "demo.say": pet.say("On it! Tests look green. [demo]", for: 4)
        case "demo.remind":
            reminders.message = "Claude Code is done and waiting for you [demo]"
            reminders.fire()
        case "trick.backflip": pet.trick(.backflip)
        case "trick.moonwalk": pet.trick(.moonwalk)
        case "demo.tryon":
            // try-on is free and unlimited; earning items comes with the Closet (milestone 5)
            let names = pet.skin.pack.gremlo.accessories?.names ?? []
            let now = pet.worn.last.flatMap { names.firstIndex(of: $0) } ?? -1
            if !names.isEmpty { pet.wornOverride = [names[(now + 1) % names.count]] }
        case "demo.undress": pet.wornOverride = []
        case let m where m.hasPrefix("mood."):
            let mood = String(m.dropFirst(5))
            pet.setMood(mood, reason: mood == "asleep" ? "demo: can't read the chain" : mood == "hungry" ? "demo: " + brokeReason : nil)
        default:
            if code == "SessionEnd" || code == "Stop" { demoHooks = nil }
            pet.handle(event: code, notification: nil)
        }
        render()
    }
    @objc func setReminder(_ sender: Seg) {
        reminderMinutes = [0.0, 2, 5, 10][max(0, sender.selectedSegment)]
        defaults.set(reminderMinutes, forKey: "reminderMinutes")
        reminders.reschedule()
    }

    @objc func toggleAllDesktops(_ sender: NSButton) {
        allDesktops = sender.state == .on
        defaults.set(allDesktops, forKey: "allDesktops")
        pet.applySpaces()
    }

    @objc func toggleSponsored(_ sender: NSButton) {
        sponsoredOn = sender.state == .on
        defaults.set(sponsoredOn, forKey: "sponsored")
        render()
    }
    @objc func toggleQuiet(_ sender: NSButton) {
        quietHours = sender.state == .on
        defaults.set(quietHours, forKey: "quietHours")
        render()
    }
    /** Hooks show only when opted in, outside quiet hours, and under the daily cap. */
    var showHooks: Bool { sponsoredOn && !inQuietHours() && (info?.impressionsToday ?? 0) < dailyViewCap }

    /** Asked once: sponsored hooks are opt-in. */
    func askSponsoredOnce() {
        guard defaults.object(forKey: "sponsored") == nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Show sponsored lines and earn while you wait?"
        a.informativeText = "While your agent works, the pet can carry one short sponsored line. Brands pay per verified view and the money goes to your pet's purse. Never during approvals, at most 120 a day, and none at night if you turn on quiet hours in Settings. You can change this any time in Settings."
        a.addButton(withTitle: "Turn on")
        a.addButton(withTitle: "Not now")
        sponsoredOn = a.runModal() == .alertFirstButtonReturn
        defaults.set(sponsoredOn, forKey: "sponsored")
        render()
    }

    @objc func setWalkSpeed(_ sender: NSSlider) { walkSpeed = sender.doubleValue; defaults.set(walkSpeed, forKey: "walkSpeed") }

    @objc func setHomeAfter(_ sender: Seg) {
        homeAfter = [30.0, 75, 180][max(0, sender.selectedSegment)]
        defaults.set(homeAfter, forKey: "homeAfter")
    }

    @objc func sendHome() { pet.goHome(lock: false) }
    @objc func toggleClaudeHooks() {
        do {
            if ClaudeHooks.isConnected { try ClaudeHooks.disconnect() } else { try ClaudeHooks.connect() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't update Claude Code's settings"
            a.informativeText = "\(error.localizedDescription)\nNothing was changed. Your settings file is at ~/.claude/settings.json."
            a.runModal()
        }
        settings.reload()
    }
    @objc func openLastCharge(_ sender: NSButton) {
        let explorer = info?.explorer ?? "https://testnet.nearblocks.io"
        if let tx = sender.identifier?.rawValue, let u = URL(string: "\(explorer)/txns/\(tx)") { NSWorkspace.shared.open(u) }
        menu.dismiss()
    }
    @objc func openPetPage() {
        let web = Legacy.env("WEB") ?? "http://localhost:3000"
        let pet = petName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? petName
        if let u = URL(string: "\(web)/me?pet=\(pet)") { NSWorkspace.shared.open(u) }
        menu.dismiss()
    }
    @objc func pairDevice() {
        guard let key = devicePublicKey else { return }
        let web = Legacy.env("WEB") ?? "http://localhost:3000"
        let pet = petName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? petName
        if let u = URL(string: "\(web)/pair?pet=\(pet)&key=\(key)") { NSWorkspace.shared.open(u) }
        menu.dismiss()
    }

    // Brings the terminal running Claude Code forward. The approval itself happens there; the app never answers a hook.
    @objc func approveInTerminal() {
        let ids = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.apple.Terminal", "com.microsoft.VSCode"]
        let app = ids.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
        app?.activate()
        menu.dismiss()
    }

    @objc func copyId(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        sender.attributedTitle = idTitle("COPIED", id, tagColor: UI.fg)
    }

    func short(_ id: String) -> String { id.count > 20 ? "\(id.prefix(10))\u{2026}\(id.suffix(8))" : id }

    func idTitle(_ tag: String, _ id: String, tagColor: NSColor) -> NSAttributedString {
        let t = NSMutableAttributedString(string: tag.padding(toLength: max(tag.count, 11), withPad: " ", startingAt: 0),
                                          attributes: [.font: UI.mono(11, .medium), .foregroundColor: tagColor, .kern: 0.4])
        t.append(NSAttributedString(string: short(id), attributes: [.font: UI.mono(11, .regular), .foregroundColor: UI.text2]))
        return t
    }

    /// Shows a shortened ID; clicking copies the full one.
    func copyButton(_ tag: String, _ id: String) -> NSView {
        let b = NSButton(title: "", target: self, action: #selector(copyId(_:)))
        b.isBordered = false
        b.alignment = .left
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.toolTip = "Copy \(id)"
        b.attributedTitle = idTitle(tag, id, tagColor: UI.accentText)
        let row = UI.hstack([b, UI.spacer()])
        row.edgeInsets = NSEdgeInsets(top: UI.rowY, left: UI.margin, bottom: UI.rowY, right: UI.margin)
        row.widthAnchor.constraint(equalToConstant: popoverWidth - UI.margin * 2).isActive = true
        return row
    }

    func avatar() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.contents = (pet.skin.strips[.idle] ?? pet.skin.strips[.walk])?.frames.first
        v.layer?.contentsGravity = .resizeAspect
        v.layer?.magnificationFilter = .nearest
        v.widthAnchor.constraint(equalToConstant: 40).isActive = true
        v.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return v
    }

    // Used by the Closet window and the privacy ledger: the same tokens as the panel.
    func bar(_ fraction: CGFloat) -> NSView { UI.bar(fraction, width: popoverWidth - UI.margin * 2) }
    func caption(_ text: String) -> NSTextField { UI.caption(text) }
    func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor = UI.text, mono: Bool = false) -> NSTextField {
        UI.label(text, mono ? UI.mono(size, weight) : UI.body(size, weight), color == .labelColor ? UI.text : color, width: popoverWidth - UI.margin * 2)
    }
    func row(_ key: String, _ value: String) -> NSView { UI.kv(key, value, width: popoverWidth - UI.margin * 2) }

    /// A section that is exactly the column width, so its label lines up with the cards above and below it.
    func column(_ views: [NSView], width: CGFloat, spacing: CGFloat = 8) -> NSView {
        let s = UI.vstack(views, spacing: spacing)
        s.widthAnchor.constraint(equalToConstant: width).isActive = true
        return s
    }
}
