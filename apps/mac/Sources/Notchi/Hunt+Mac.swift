import AppKit
import CryptoKit
import EventKit
import NotchiCore

// Round 4 §2-10 on the Mac. Rules in NotchiCore/Hunt.swift. Nothing here leaves the Mac.

/// The props sheet (assets/props): bugs, dream icons, seasonal scenery. 2 pt per sheet unit, like the pets.
enum Props {
    static let sheet: CGImage? = Images.load(assetsDir.appendingPathComponent("props/props.png"))
    static let rects: [String: CGRect] = {
        guard let d = try? Data(contentsOf: assetsDir.appendingPathComponent("props/props.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let items = o["items"] as? [String: [String: Double]] else { return [:] }
        return items.mapValues { CGRect(x: $0["x"] ?? 0, y: $0["y"] ?? 0, width: $0["w"] ?? 0, height: $0["h"] ?? 0) }
    }()
    static var cache: [String: CGImage] = [:]
    static func image(_ name: String) -> CGImage? {
        if let c = cache[name] { return c }
        guard let r = rects[name], let img = sheet?.cropping(to: r) else { return nil }
        cache[name] = img
        return img
    }
    static func size(_ name: String) -> CGSize { rects[name].map { CGSize(width: $0.width * 2, height: $0.height * 2) } ?? CGSize(width: 20, height: 20) }

    /// A borderless click-through (unless `clickable`) panel showing one prop.
    static func panel(_ name: String, clickable: Bool = false) -> NSPanel {
        let p = overlayPanel(size(name), level: .statusBar)
        p.ignoresMouseEvents = !clickable
        p.contentView?.layer?.contents = image(name)
        p.contentView?.layer?.magnificationFilter = .nearest
        return p
    }
}

final class HuntController {
    unowned let backend: Backend
    var hunt: BugHunt
    var bugPanels: [Int: (panel: NSPanel, dir: CGFloat)] = [:]
    var stuck = StuckDetector()
    var stuckTrigger: StuckTrigger?
    var dreams = DreamLog()
    var dreamsDay = WaitClock.dayOf(Date())
    var cwds: Set<String> = []
    var conflicted = false
    var sessionTools: [String: Int] = [:]
    var lastShowOff: Date?
    var scenery: [NSPanel] = []
    var season: Season?
    let store = EKEventStore()
    var nextMeeting: (title: String, start: Date, end: Date)?
    var inMeeting = false
    var frameTick = 0
    var pet: Pet { backend.pet }

    static var seasonsOn: Bool { defaults.object(forKey: "seasons") as? Bool ?? true }
    static var meetingsOn: Bool { defaults.bool(forKey: "meetings") }  // EventKit only with permission: opt-in
    static var extraRunners: [String] { defaults.stringArray(forKey: "testRunners") ?? [] }

    init(backend: Backend) {
        self.backend = backend
        hunt = BugHunt(jar: backend.growth.p.bugJar)
        if let d = defaults.data(forKey: "dreams.\(dreamsDay)"), let log = try? JSONDecoder().decode(DreamLog.self, from: d) { dreams = log }
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.crawl() }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.watchMerge() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.slowTick() }
        applySeason()
        slowTick()
    }

    // MARK: Hook events

    func hook(_ h: [String: Any]) {
        let ev = h["hook_event_name"] as? String ?? ""
        let tool = h["tool_name"] as? String
        let input = h["tool_input"] as? [String: Any] ?? [:]
        let command = input["command"] as? String
        let session = h["session_id"] as? String ?? ""
        if let cwd = h["cwd"] as? String { cwds.insert(cwd) }
        switch ev {
        case "PreToolUse":
            sessionTools[session, default: 0] += 1
            backend.growth.sessionTools(sessionTools[session] ?? 0)
            if let f = input["file_path"] as? String, Step.kind(tool: tool ?? "") == .edit { _ = fileEdited(f) }  // the version before
        case "PostToolUse":
            if Step.kind(tool: tool ?? "") == .edit { dream(.wrench); if let f = input["file_path"] as? String, let t = fileEdited(f) { fire(t) } }
        case "PostToolUseFailure":
            if let err = h["error"] as? String, h["is_interrupt"] as? Bool != true, let t = stuck.failure(tool: tool ?? "", error: err, at: Date()) { fire(t) }
        case "Stop", "StopFailure":
            stuck.runEnded(); stuckTrigger = nil
            if ev == "Stop" { dream(.star) }
        case "SessionEnd":
            sessionTools[session] = nil
            clearBugs()
        default: break
        }
        if let ok = TestRun.outcome(event: ev, tool: tool, command: command, interrupted: h["is_interrupt"] as? Bool ?? false, extra: Self.extraRunners) {
            dream(.flask)
            if ok { dream(.check); caught() } else { dream(.bug); spawnBug() }
        }
    }

    private func fileEdited(_ path: String) -> StuckTrigger? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        let hash = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
        return stuck.edited(file: path, hash: hash, at: Date())
    }

    // MARK: Stuck (R4 §3): the notch says so; it never stops or messages the agent

    private func fire(_ t: StuckTrigger) {
        stuckTrigger = t
        print("stuck: \(t.kind) \(t.count)x")
        if pet.path == .floor { pet.set(.flag, then: .walk) }
        Feel.sound("approval")
        backend.live.update()
    }
    func ignoreRun() { stuck.ignoreRun(); stuckTrigger = nil; backend.live.update() }
    func copyNudge() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(StuckDetector.nudge, forType: .string)
    }

    // MARK: Bugs (R4 §2)

    private var floorY: CGFloat { mainScreen.visibleFrame.minY }

    func spawnBug() {
        let f = mainScreen.visibleFrame
        let x = CGFloat.random(in: f.minX + 40...f.maxX - 60)
        guard let bug = hunt.failed(at: Double(x)) else { return }
        let p = Props.panel("bug0", clickable: true)
        let click = ClickView(frame: CGRect(origin: .zero, size: p.frame.size))
        click.autoresizingMask = [.width, .height]
        click.onClick = { [weak self] in self?.squash(bug.id) }
        p.contentView?.addSubview(click)
        p.setFrameOrigin(NSPoint(x: x, y: floorY))
        p.orderFrontRegardless()
        bugPanels[bug.id] = (p, Bool.random() ? 1 : -1)
        if pet.path == .floor && !pet.busy { pet.set(.gaze, then: .walk) }  // the earner watches; companions would chase
    }

    private func crawl() {
        frameTick += 1
        if frameTick % 10 == 0 { chase() }
        let f = mainScreen.visibleFrame
        for b in hunt.bugs {
            guard var e = bugPanels[b.id] else { continue }
            var x = e.panel.frame.minX + e.dir * 1.2
            if x < f.minX || x > f.maxX - e.panel.frame.width { e.dir *= -1; x = min(max(x, f.minX), f.maxX - e.panel.frame.width); bugPanels[b.id] = e }
            e.panel.setFrameOrigin(NSPoint(x: x, y: floorY))
            if frameTick % 2 == 0 { e.panel.contentView?.layer?.contents = Props.image("bug\((frameTick / 2) % 4)") }
            e.panel.contentView?.layer?.transform = CATransform3DMakeScale(e.dir < 0 ? -1 : 1, 1, 1)
            hunt.move(b.id, to: Double(x))
        }
    }

    func squash(_ id: Int) {
        guard hunt.squash(id), let e = bugPanels.removeValue(forKey: id) else { return }
        e.panel.contentView?.layer?.contents = Props.image("bugsquash")
        NSAnimationContext.runAnimationGroup({ $0.duration = 1; e.panel.animator().alphaValue = 0 }) { e.panel.orderOut(nil) }
        if pet.path == .floor { pet.set(.fail, then: .walk) }  // a beat of sulking
    }

    /// Every pet on the bottom edge, earner first (companions perched on a window don't count).
    var floorPets: [Pet] { ([pet] + Array(backend.companions.pets.values)).filter { $0.path == .floor && $0.perch == nil && !$0.ducked } }

    /// A passing run: the nearest pet walks to each bug in turn, pounces and gulps it. Each one goes in the jar.
    func caught() {
        let catcher = floorPets.first
        let eaten = hunt.passed(petX: Double(catcher?.pos.x ?? pet.pos.x))
        backend.growth.setBugJar(hunt.jar)
        var panels = eaten.compactMap { b in bugPanels.removeValue(forKey: b.id).map { ($0.panel, $0.panel.frame.midX) } }
        func next() {
            guard !panels.isEmpty else { return }
            let (panel, x) = panels.removeFirst()
            // the nearest free pet to this bug catches it; if nobody is out, the bug just leaves (still counted)
            guard let p = floorPets.min(by: { abs($0.pos.x + $0.size.width / 2 - x) < abs($1.pos.x + $1.size.width / 2 - x) }) else { panel.orderOut(nil); next(); return }
            p.target = (x, { [weak p] in
                panel.orderOut(nil)
                p?.set(.gulp, then: .walk)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { next() }
            })
        }
        next()
    }

    /// Companions chase bugs but never catch them until a pass; the earner only watches (R4 §2).
    private func chase() {
        guard !hunt.bugs.isEmpty else { return }
        for c in backend.companions.pets.values where c.path == .floor && c.perch == nil && !c.busy && c.target == nil {
            guard let b = hunt.bugs.min(by: { abs($0.x - Double(c.pos.x)) < abs($1.x - Double(c.pos.x)) }) else { continue }
            let x = CGFloat(b.x), side: CGFloat = c.pos.x < x ? -40 : 40
            if abs(c.pos.x + c.size.width / 2 - (x + side)) > 30 { c.target = (x + side, {}) }
        }
    }

    func clearBugs() {
        hunt.clear()
        for e in bugPanels.values { e.panel.orderOut(nil) }
        bugPanels = [:]
    }

    // MARK: Git (R4 §4)

    func git(_ e: GitEvent) {
        print("git: \(e.rawValue)")
        switch e {
        case .tag:
            backend.growth.releaseTag()
            pet.trick(.moonwalk)
        case .merged: dream(.merge); if pet.path == .floor { pet.set(.celebrate, then: .walk) }
        case .commit: if pet.path == .floor && !pet.busy { pet.set(.greet, then: .walk) }
        case .forcePush: if pet.path == .floor { pet.set(.covereyes, then: .walk) }
        case .conflict: break
        }
    }

    private func watchMerge() {
        let now = cwds.contains { GitWatch.conflicted($0) }
        guard now != conflicted else { return }
        conflicted = now
        if now { if pet.path == .floor { pet.set(.tangled) } }
        else { dream(.merge); if pet.state == .tangled { pet.set(.land, then: .walk) } }  // shakes free
    }

    // MARK: Dreams (R4 §7)

    func dream(_ d: Dream) {
        let today = WaitClock.dayOf(Date())
        if today != dreamsDay { dreamsDay = today; dreams = DreamLog() }
        dreams.add(d)
        if let data = try? JSONEncoder().encode(dreams) { defaults.set(data, forKey: "dreams.\(dreamsDay)") }
    }

    // MARK: Tricks, seasons, meetings

    private func slowTick() {
        // tricks: learned ones may show off, at most once an hour, only while idle
        let learned = backend.growth.tricks
        let idle = pet.path == .floor && [.walk, .idle].contains(pet.state) && !pet.busy
        if let t = learned.randomElement(), Trick.mayShowOff(last: lastShowOff, now: Date(), idle: idle) {
            lastShowOff = Date()
            doTrick(t)
        }
        let s = Self.seasonsOn ? Season.current(Date(), region: Locale.current.region?.identifier) : nil
        if s != season { applySeason() }
        checkMeetings()
    }

    func doTrick(_ t: Trick) {
        switch t {
        case .backflip: pet.trick(.backflip)
        case .moonwalk: pet.trick(.moonwalk)
        case .juggle: if pet.path == .floor { pet.set(.juggle, then: .walk) }
        }
    }

    /// Scenery only: nothing to collect, nothing for sale. Off in one click.
    func applySeason() {
        scenery.forEach { $0.orderOut(nil) }
        scenery = []
        season = Self.seasonsOn ? Season.current(Date(), region: Locale.current.region?.identifier) : nil
        let f = mainScreen.visibleFrame
        switch season {
        case .diwali:
            for i in 0..<5 {
                let p = Props.panel("s-diya")
                p.setFrameOrigin(NSPoint(x: f.minX + f.width * CGFloat(i + 1) / 6, y: f.minY))
                scenery.append(p)
            }
            let lantern = Props.panel("s-lantern")
            lantern.setFrameOrigin(NSPoint(x: mainScreen.frame.midX + 70, y: f.maxY - lantern.frame.height))
            scenery.append(lantern)
        case .october:
            let p = Props.panel("s-pumpkin")
            p.setFrameOrigin(NSPoint(x: f.minX + 24, y: f.minY))
            scenery.append(p)
        case .winter:
            for _ in 0..<Season.maxSnow {
                let p = Props.panel("s-snow")
                p.setFrameOrigin(NSPoint(x: CGFloat.random(in: f.minX...f.maxX), y: CGFloat.random(in: f.minY...f.maxY)))
                scenery.append(p)
            }
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] t in
                guard let self, self.season == .winter else { t.invalidate(); return }
                for p in self.scenery {
                    var o = p.frame.origin
                    o.y -= 1.5; o.x += CGFloat.random(in: -0.6...0.6)
                    if o.y < f.minY { o = NSPoint(x: CGFloat.random(in: f.minX...f.maxX), y: f.maxY) }
                    p.setFrameOrigin(o)
                }
            }
        case nil: break
        }
        if pet.onHomeSpace { scenery.forEach { $0.orderFrontRegardless() } }
    }

    /// EventKit, only with permission; titles stay on this Mac.
    func enableMeetings(_ on: Bool) {
        defaults.set(on, forKey: "meetings")
        guard on else { nextMeeting = nil; return }
        let done: (Bool, Error?) -> Void = { granted, _ in DispatchQueue.main.async { if !granted { defaults.set(false, forKey: "meetings") }; self.checkMeetings() } }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: done) } else { store.requestAccess(to: .event, completion: done) }
    }

    private func checkMeetings() {
        guard Self.meetingsOn else { nextMeeting = nil; inMeeting = false; return }
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(600), calendars: nil)
        let ev = store.events(matching: pred).filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }.first
        let before = nextMeeting.map { HeadsUp.state(start: $0.start, end: $0.end, now: now) } ?? HeadsUp.none
        nextMeeting = ev.map { ($0.title ?? "meeting", $0.startDate, $0.endDate) }
        let state = nextMeeting.map { HeadsUp.state(start: $0.start, end: $0.end, now: now) } ?? HeadsUp.none
        if case .soon = state, before == HeadsUp.none, pet.path == .floor { pet.set(.wrist, then: .walk) }  // checks its watch
        if state == .inMeeting && !inMeeting { pet.set(.greet); pet.goHome(lock: false) }  // waves, goes home
        inMeeting = state == .inMeeting
        silence.inMeeting = inMeeting
        backend.live.update()
    }

    var meetingSoonText: String? {
        guard let m = nextMeeting, case let .soon(mins) = HeadsUp.state(start: m.start, end: m.end, now: Date()) else { return nil }
        let left = max(0, Int(m.start.timeIntervalSinceNow))
        return "\(m.title.lowercased()) in \(mins) \u{00B7} \(left / 60):\(String(format: "%02d", left % 60))"
    }
}

// MARK: - Drop zone (R4 §5): the notch takes drops and puts them on the clipboard. Nothing uploads or types.

final class DropView: NSView {
    var onDragging: ((Bool) -> Void)?
    var onScroll: ((NSEvent) -> Void)?
    override func scrollWheel(with e: NSEvent) { onScroll?(e) }
    var onDropped: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string, .png, .tiff])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { onDragging?(true); return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragging?(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onDragging?(false) }
        let pb = sender.draggingPasteboard
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let out = NSPasteboard.general
        out.clearContents()
        if !urls.isEmpty {
            let text = DropZone.text(paths: urls.map(\.path))
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            // an image goes on as the image too, for agents that take pasted images
            if urls.count == 1, DropZone.isImage(urls[0].path), let img = NSImage(contentsOf: urls[0]), let tiff = img.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
                if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
            }
            out.writeObjects([item])
        } else if let img = NSImage(pasteboard: pb) {
            out.writeObjects([img])
        } else if let s = pb.string(forType: .string) {
            out.setString(s, forType: .string)
        } else { return false }
        onDropped?()
        return true
    }
}

// MARK: - Session scrubber (R4 §6): one bar per step; drag to read, click to copy the command or open the file

final class ScrubView: NSView {
    var steps: [Step] = [] { didSet { needsDisplay = true } }
    var accent = NSColor.white
    var onHover: ((String) -> Void)?
    private var picked: Int?

    func color(_ k: Step.Kind) -> NSColor {
        switch k {
        case .read: return accent.withAlphaComponent(0.45)
        case .edit: return accent.withAlphaComponent(0.75)
        case .run: return accent
        case .failed: return .systemRed
        case .approval: return .white
        case .passed: return .systemGreen
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !steps.isEmpty else { return }
        let w = bounds.width / CGFloat(steps.count)
        for (i, s) in steps.enumerated() {
            color(s.kind).setFill()
            let h: CGFloat = s.kind == .read ? 6 : s.kind == .edit ? 9 : 12
            NSRect(x: CGFloat(i) * w, y: 0, width: max(1.5, w - 1.5), height: i == picked ? 14 : h).fill()
        }
    }

    private func index(_ e: NSEvent) -> Int? {
        guard !steps.isEmpty else { return nil }
        let x = convert(e.locationInWindow, from: nil).x
        return min(max(Int(x / (bounds.width / CGFloat(steps.count))), 0), steps.count - 1)
    }
    private func show(_ i: Int?) {
        picked = i
        needsDisplay = true
        guard let i else { return }
        let s = steps[i]
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        onHover?("\(f.string(from: s.start)) \u{00B7} \(s.tool) \u{00B7} \(s.summary)")
    }
    override func mouseDown(with e: NSEvent) { show(index(e)) }
    override func mouseDragged(with e: NSEvent) { show(index(e)) }
    override func mouseUp(with e: NSEvent) {
        guard let i = index(e) else { return }
        let s = steps[i]
        if let c = s.command {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(c, forType: .string)
            onHover?("copied: \(String(c.prefix(60)))")
        } else if let f = s.file, FileManager.default.fileExists(atPath: f) {
            NSWorkspace.shared.open(URL(fileURLWithPath: f))
        }
    }
}

/// Runs kept on this Mac for 7 days (R4 §6).
enum RunLog {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Notchi/runs")
    static func save(_ steps: [Step]) {
        guard !steps.isEmpty else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? enc.encode(steps).write(to: dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970)).json"))
        let old = Date().addingTimeInterval(-Step.keepDays * 86400)
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d < old { try? FileManager.default.removeItem(at: f) }
        }
    }
}

// MARK: - Settings rows

extension Backend {
    func huntControls() -> [NSView] {
        let seasons = NSButton(checkboxWithTitle: "Seasonal scenery", target: self, action: #selector(toggleSeasons(_:)))
        seasons.state = HuntController.seasonsOn ? .on : .off
        let meetings = NSButton(checkboxWithTitle: "Meeting heads-up (asks for Calendar access; titles stay on this Mac)", target: self, action: #selector(toggleMeetings(_:)))
        meetings.state = HuntController.meetingsOn ? .on : .off
        let runners = NSTextField(string: HuntController.extraRunners.joined(separator: ", "))
        runners.placeholderString = "more test commands, e.g. make check, ./run-tests"
        runners.target = self
        runners.action = #selector(setRunners(_:))
        let gh = NSButton(checkboxWithTitle: GitHubController.gh == nil ? "GitHub: install the gh CLI to celebrate merges" : "GitHub (your gh CLI): celebrate merged PRs, send my companion when I ask for a review", target: self, action: #selector(toggleGitHub(_:)))
        gh.state = GitHubController.on ? .on : .off
        gh.isEnabled = GitHubController.gh != nil
        let add = NSButton(title: "Add git hooks to a repo\u{2026}", target: self, action: #selector(installGitHooks))
        let remove = NSButton(title: "Remove git hooks from a repo\u{2026}", target: self, action: #selector(removeGitHooks))
        return [caption("Extras"), seasons, meetings, caption("Test commands (bug hunt)"), runners, caption("Git moods (no messages, diffs or file names are sent)"), add, remove, gh]
    }

    @objc func toggleGitHub(_ b: NSButton) { defaults.set(b.state == .on, forKey: "github"); if b.state == .on { defaults.set(Date(), forKey: "github.since"); github.tick() } }
    @objc func toggleSeasons(_ b: NSButton) { defaults.set(b.state == .on, forKey: "seasons"); hunt.applySeason() }
    @objc func toggleMeetings(_ b: NSButton) { hunt.enableMeetings(b.state == .on) }
    @objc func setRunners(_ f: NSTextField) {
        let list = f.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // user patterns are matched as regular expressions; drop any that don't compile
        defaults.set(list.filter { (try? NSRegularExpression(pattern: $0)) != nil }, forKey: "testRunners")
    }

    func pickRepo() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Choose repo"
        NSApp.activate(ignoringOtherApps: true)
        return p.runModal() == .OK ? p.url?.path : nil
    }
    @objc func installGitHooks() {
        guard let repo = pickRepo(), let script = Bundle.main.url(forResource: "notchi-git-hook", withExtension: "sh") ?? Bundle.module.url(forResource: "notchi-git-hook", withExtension: "sh") else { return }
        do { try GitHooks.install(repo: repo, script: script); print("git hooks added to a repo") }
        catch { pet.say("Couldn't add git hooks: \(error.localizedDescription)", for: 5) }
    }
    @objc func removeGitHooks() {
        guard let repo = pickRepo() else { return }
        do { try GitHooks.remove(repo: repo); print("git hooks removed from a repo") }
        catch { pet.say("Couldn't remove git hooks: \(error.localizedDescription)", for: 5) }
    }
}

// MARK: - GitHub through the user's gh CLI (opt-in): merged PRs celebrate, review requests send your companion

final class GitHubController {
    unowned let backend: Backend
    static var on: Bool { defaults.bool(forKey: "github") }
    static let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    private var seen = Set(defaults.stringArray(forKey: "github.seen") ?? [])

    init(backend: Backend) {
        self.backend = backend
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func run(_ args: [String], done: @escaping (Data?) -> Void) {
        guard let gh = Self.gh else { done(nil); return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: gh); p.arguments = args
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            guard (try? p.run()) != nil else { DispatchQueue.main.async { done(nil) }; return }
            let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            DispatchQueue.main.async { done(p.terminationStatus == 0 ? d : nil) }
        }
    }

    func tick() {
        guard Self.on else { return }
        let since = defaults.object(forKey: "github.since") as? Date ?? Date().addingTimeInterval(-300)
        let iso = ISO8601DateFormatter().string(from: since)
        // merged PRs of mine since the last check: celebrate with fireworks from the notch
        run(["search", "prs", "--author=@me", "--merged", "--merged-at=>\(iso)", "--json", "url"]) { [weak self] d in
            guard let self, let d, let list = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
            defaults.set(Date(), forKey: "github.since")
            if !list.isEmpty { self.backend.hunt.git(.merged) }
        }
        // review requests on my open PRs: my companion visits each newly asked teammate (team handles = GitHub logins)
        let q = "query{viewer{pullRequests(states:OPEN,first:30,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{url reviewRequests(first:10){nodes{requestedReviewer{... on User{login}}}}}}}}"
        let shape = "[.data.viewer.pullRequests.nodes[] | {url, reviewRequests: [.reviewRequests.nodes[].requestedReviewer | select(.login != null) | {login}]}]"
        run(["api", "graphql", "-f", "query=\(q)", "--jq", shape]) { [weak self] d in
            guard let self, let d else { return }
            let r = GitHubWatch.newRequests(GitHubWatch.parse(d), seen: self.seen)
            self.seen = r.seen
            defaults.set(Array(r.seen.suffix(500)), forKey: "github.seen")
            for v in r.new where !SocialController.team.isEmpty { self.backend.social.sendVisit(to: v.reviewer, pr: v.url) }
        }
    }
}
