import AppKit
import Carbon
import CoreAudio
import CoreMediaIO
import Network
import NotchiCore

// Privacy (base §9), focus (R2 §12), the room and guestbook (R4 §11-12), stream mode (R4 §13) and the weekly
// postcard (R4 §15). Rules in NotchiCore/Room.swift.

final class PrivacyController {
    unowned let backend: Backend
    var duck = Duck.none
    var focus: FocusSession?
    var limiter = LineLimiter()
    var lineWasUp = false
    var stream: StreamServer?
    var pet: Pet { backend.pet }

    static var streamOn: Bool { defaults.bool(forKey: "streamMode") }
    static var visitsOn: Bool { defaults.bool(forKey: "visits") }  // the host allows visits; off by default

    init(backend: Backend) {
        self.backend = backend
        HotKeys.install()
        HotKeys.register(1, keyCode: UInt32(kVK_ANSI_P), mods: UInt32(cmdKey | optionKey)) { [weak self] in self?.togglePause() }
        HotKeys.register(2, keyCode: UInt32(kVK_ANSI_F), mods: UInt32(cmdKey | optionKey)) { [weak self] in self?.toggleFocus(25) }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.detect() }
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.postcardTick() }
        if Self.streamOn { setStream(true) }
    }

    // MARK: Detectors (always on, no setting)

    func detect() {
        silence.screenShared = Detect.screenShared()
        silence.fullScreenVideo = Detect.fullScreen()
        let micMeeting = Detect.micInUse() || Detect.cameraInUse()
        silence.inMeeting = micMeeting || backend.hunt.inMeeting
        let d = Duck.decide(screenShared: silence.screenShared, inMeeting: silence.inMeeting, focus: silence.focus,
                            fullScreen: silence.fullScreenVideo, streamMode: Self.streamOn)
        if silence.screenShared && !Self.streamOn { backend.hunt.clearBugs() }  // bugs leave on a share too
        let changed = d != duck
        if changed { print("privacy: \(duck) -> \(d)") }
        duck = d
        let hide = d == .intoNotch || d == .hidden
        // applied on every check, so a companion or visitor that arrives mid-share is hidden too
        for p in [pet] + Array(backend.companions.pets.values) + backend.social.visitors {
            if p.ducked != hide {
                for w in [p.panel, p.signPanel, p.bubblePanel] { w.alphaValue = hide ? 0 : 1; if hide { w.ignoresMouseEvents = true } }
                p.ducked = hide
            }
            if changed && (d == .sleep || d == .home) { p.goHome(lock: false) }
        }
        guard changed else { return }
        backend.shown = ""
        backend.render()
    }

    /// True when a sponsored line may be up right now. Focus, stream mode, a pause, an egg, a share, a meeting or
    /// full screen all mean no line; and no more than 12 new lines an hour.
    func lineAllowed(_ text: String?) -> Bool {
        guard text != nil else { lineWasUp = false; return false }
        if focus != nil || Self.streamOn || backend.paused || pet.egg || silence.silent || duck != .none { lineWasUp = false; return false }
        // never during fail, celebrate or an approval (R2 §15)
        if [.fail, .celebrate, .flag].contains(pet.state) || pet.waiting || !backend.broker.queue.waiting.isEmpty { lineWasUp = false; return false }
        if !lineWasUp {
            // brand alternation needs a second campaign to alternate with; the server picks campaigns (shortcut)
            guard limiter.allows(brand: "", now: Date()) else { return false }
            limiter.record(brand: "", now: Date())
            lineWasUp = true
        }
        return true
    }

    // MARK: Pause (⌥⌘P) and focus (⌥⌘F)

    func togglePause() {
        if backend.paused { backend.pausedUntil = .distantPast; print("pause off"); backend.shown = ""; backend.render() }
        else { backend.pause(minutes: 30) }
    }

    func toggleFocus(_ minutes: Int) {
        if focus != nil { endFocus(finished: false); return }
        focus = FocusSession(start: Date(), minutes: minutes)
        silence.focus = true
        Feel.sound("focus-start")
        if pet.path == .floor { pet.set(.focus) } else { pet.comeOut(then: .focus) }
        print("focus: \(minutes) min, lines off")
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, let f = self.focus else { t.invalidate(); return }
            if f.finished(Date()) { t.invalidate(); self.endFocus(finished: true) }
            self.backend.live.update()
        }
        backend.shown = ""; backend.render(); backend.live.update()
    }

    /// Ending early is fine: no guilt screen, no streak. A finished session earns 2 stars.
    func endFocus(finished: Bool) {
        guard let f = focus else { return }
        focus = nil
        silence.focus = false
        if finished { backend.growth.focusFinished(id: "\(Int(f.start.timeIntervalSince1970))"); Feel.sound("focus-end") }
        if pet.state == .focus { pet.set(.walk) }
        backend.shown = ""; backend.render(); backend.live.update()
    }

    // MARK: Stream mode

    func setStream(_ on: Bool) {
        defaults.set(on, forKey: "streamMode")
        stream?.stop()
        stream = on ? StreamServer(backend: backend) : nil
        backend.shown = ""; backend.render()
    }

    // MARK: Postcard (Sunday 18:00)

    static let postcardDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Notchi/postcards")

    func postcardTick() {
        let last = defaults.object(forKey: "postcard.last") as? Date
        guard Postcard.due(now: Date(), lastSent: last) else { return }
        makePostcard()
    }

    @discardableResult
    func makePostcard() -> URL? {
        let g = backend.growth
        var w = WeekCounts()
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let runs = (try? FileManager.default.contentsOfDirectory(at: RunLog.dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        w.runs = runs.filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > weekAgo }.count
        w.bugs = max(0, g.p.bugJar - defaults.integer(forKey: "postcard.jar"))
        let knew = Set(defaults.stringArray(forKey: "postcard.tricks") ?? [])
        w.trick = g.tricks.map(\.rawValue).first { !knew.contains($0) }
        w.outfit = g.worn
        let kind = Roster.species(pet.skin.name)?.kind ?? "pet"
        let lines = Postcard.lines(name: g.petDisplayName, species: kind, w: w)
        let frame = (pet.skin.strips[.celebrate] ?? pet.skin.strips[.walk])?.frames.first
        guard let img = Postcard.render(lines: lines, pet: frame, accent: pet.skin.accent), let png = Images.png(img) else { return nil }
        try? FileManager.default.createDirectory(at: Self.postcardDir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = Self.postcardDir.appendingPathComponent("\(f.string(from: Date())).png")
        try? png.write(to: url)
        defaults.set(Date(), forKey: "postcard.last")
        defaults.set(g.p.bugJar, forKey: "postcard.jar")
        defaults.set(g.tricks.map(\.rawValue), forKey: "postcard.tricks")
        print("postcard: saved")
        backend.rebuildGrowth()
        return url
    }

    var latestPostcard: URL? {
        ((try? FileManager.default.contentsOfDirectory(at: Self.postcardDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }.max { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: Guestbook (visits arrive from the server's relay, M9)

    func visit(_ payload: [String: Any]) {
        guard Self.visitsOn, let e = GuestbookEntry.from(payload, at: Date()) else { return }
        backend.growth.addGuest(e)
        print("guestbook: a \(e.species) visited")
    }

    // MARK: Export and delete (one button each)

    static let supportDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Notchi")
    static var domain: String { Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName }

    func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "notchi-data.json"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        var out: [String: Any] = [:]
        // keys, tokens and pairings stay out of the file (never print keys)
        let secret = ["pairing", "token", "key", "secret"]
        let prefs = (defaults.persistentDomain(forName: Self.domain) ?? [:]).filter { k, _ in !secret.contains { k.lowercased().contains($0) } }
        out["settings"] = prefs.mapValues { v -> Any in
            if let d = v as? Data { return (try? JSONSerialization.jsonObject(with: d)) ?? d.base64EncodedString() }
            if let d = v as? Date { return ISO8601DateFormatter().string(from: d) }
            return v
        }
        var files: [String: String] = [:]
        for sub in ["diary", "runs"] {
            let dir = Self.supportDir.appendingPathComponent(sub)
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                files["\(sub)/\(f.lastPathComponent)"] = try? String(contentsOf: f, encoding: .utf8)
            }
        }
        out["files"] = files
        if let d = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: url) }
    }

    func deleteAll() {
        let a = NSAlert()
        a.messageText = "Delete everything this app keeps on this Mac?"
        a.informativeText = "Growth, stars, Closet, room, guestbook, diary, runs, postcards and settings. The pairing key in ~/.notchi stays until you disconnect."
        a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        defaults.removePersistentDomain(forName: Self.domain)
        try? FileManager.default.removeItem(at: Self.supportDir)
        print("privacy: local data deleted, quitting")
        NSApp.terminate(nil)
    }
}

// MARK: - Detection, all local

enum Detect {
    /// Processes that only run while the screen is shared or recorded.
    /// shortcut: a process-name list (Zoom's share host, the system recorder); browser-based sharing isn't seen.
    static let sharing: Set<String> = ["CptHost", "screencaptureui"]

    static func screenShared() -> Bool {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var name = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(0, count))) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0, sharing.contains(String(cString: name)) { return true }
        }
        return false
    }

    /// The default microphone is in use by some app: treat as a call.
    static func micInUse() -> Bool {
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr, dev != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Any camera is in use by some app: a call.
    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0, got: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0, running != 0 { return true }
        }
        return false
    }

    /// Another app's window covers the whole main screen (full-screen video, a presentation).
    static func fullScreen() -> Bool {
        let screen = mainScreen.frame.size
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (b["Width"] ?? 0) >= screen.width && (b["Height"] ?? 0) >= screen.height
        }
    }
}

// MARK: - Global hot keys (Carbon; no permission needed)

enum HotKeys {
    static var handlers: [UInt32: () -> Void] = [:]
    static var refs: [EventHotKeyRef?] = []

    static func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            DispatchQueue.main.async { HotKeys.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    static func register(_ id: UInt32, keyCode: UInt32, mods: UInt32, _ fn: @escaping () -> Void) {
        handlers[id] = fn
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, mods, EventHotKeyID(signature: OSType(0x4E544348), id: id), GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

// MARK: - Stream mode server: 127.0.0.1 only, /overlay and /events (SSE) for an OBS browser source

final class StreamServer {
    static let port: UInt16 = 47475
    let listener: NWListener?
    var clients: [NWConnection] = []
    unowned let backend: Backend
    var timer: Timer?

    init(backend: Backend) {
        self.backend = backend
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
        listener?.newConnectionHandler = { [weak self] c in c.start(queue: .main); self?.read(c) }
        listener?.start(queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.push() }
        print("stream mode: overlay on http://127.0.0.1:\(Self.port)/overlay")
    }

    func stop() { timer?.invalidate(); clients.forEach { $0.cancel() }; listener?.cancel() }

    private func read(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data else { c.cancel(); return }
            let path = String(decoding: data, as: UTF8.self).split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            switch path {
            case "/events":
                c.send(content: Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                self.clients.append(c)
                self.push()
            case "/pet.png":
                let frame = (self.backend.pet.skin.strips[.idle] ?? self.backend.pet.skin.strips[.walk])?.frames.first
                self.send(c, type: "image/png", body: frame.flatMap(Images.png) ?? Data())
            default:
                self.send(c, type: "text/html; charset=utf-8", body: Data(Self.page.utf8))
            }
        }
    }

    private func send(_ c: NWConnection, type: String, body: Data) {
        var r = Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        r.append(body)
        c.send(content: r, completion: .contentProcessed { _ in c.cancel() })
    }

    private func push() {
        guard !clients.isEmpty else { return }
        let b = backend
        let payload = StreamOverlay.payload(name: b.growth.petDisplayName, species: b.pet.skin.name, stage: b.growth.p.stage, mood: b.pet.mood,
                                            tools: b.run.tools, waiting: !b.broker.queue.waiting.isEmpty || b.pet.waiting)
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let msg = Data("data: ".utf8) + json + Data("\n\n".utf8)
        clients = clients.filter { c in
            if case .cancelled = c.state { return false }
            if case .failed = c.state { return false }
            c.send(content: msg, completion: .contentProcessed { _ in })
            return true
        }
    }

    static let page = """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html,body{margin:0;background:transparent;font:600 18px -apple-system,system-ui,sans-serif;color:#fff;text-shadow:0 1px 3px #000}
    .pet{display:flex;align-items:flex-end;gap:12px;padding:12px}img{width:96px;image-rendering:pixelated}
    .s{opacity:.85;font-weight:500;font-size:15px}
    </style></head><body><div class="pet"><img src="/pet.png" alt=""><div><div id="n"></div><div class="s" id="s"></div></div></div>
    <script>
    const es=new EventSource('/events');
    es.onmessage=e=>{const d=JSON.parse(e.data);document.getElementById('n').textContent=d.name+' \\u00b7 '+d.mood;
    document.getElementById('s').textContent=d.tools+' tools \\u00b7 '+d.status};
    </script></body></html>
    """
}

// MARK: - The room in the notch (pull the notch down)

final class RoomView: NSView {
    unowned let backend: Backend
    init(backend: Backend, size: NSSize, top: CGFloat) {
        self.backend = backend
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        let g = backend.growth.p
        let u = min(size.width / CGFloat(Room.size.w), (size.height - top) / CGFloat(Room.size.h))
        let ox = (size.width - CGFloat(Room.size.w) * u) / 2
        func place(_ img: CGImage?, unitX: Int, unitY: Int, w: CGFloat, h: CGFloat) -> CALayer {
            let l = CALayer()
            l.contents = img
            l.magnificationFilter = .nearest
            l.contentsGravity = .resizeAspect
            // spots are the piece's top-left in room units, y down from the top
            l.frame = CGRect(x: ox + CGFloat(unitX) * u, y: size.height - top - CGFloat(unitY) * u - h, width: w, height: h)
            layer?.addSublayer(l)
            return l
        }
        for f in Room.items where g.placed.contains(f.id) {
            let r = Props.rects[f.prop] ?? .zero
            let l = place(Props.image(f.prop), unitX: f.x, unitY: f.y, w: r.width * u, h: r.height * u)
            l.name = f.id
        }
        let spot = Room.petSpot(placed: g.placed, night: backend.pet.night, agentWorking: backend.pet.working)
        let strip = backend.pet.skin.strips.first { $0.value.row == spot.row }?.value ?? backend.pet.skin.strips[.idle]
        let ph = 40 * u / 2.2, pw = ph * 192 / 208
        let px = spot.item.map { $0.x + 4 } ?? 80, py = spot.item.map { $0.y - 14 } ?? 74
        let petLayer = place(strip?.frames.first, unitX: px, unitY: py, w: pw, h: ph)
        // the pet in the room moves through its row at the spec rate (a still frame looked stuffed)
        let frames = strip?.frames ?? [], fps = Rates.fps(spot.row, mood: backend.pet.mood) ?? 6
        if frames.count > 1 {
            var f = 0
            Timer.scheduledTimer(withTimeInterval: 1 / max(fps, 1), repeats: true) { [weak self, weak petLayer] t in
                guard self?.window != nil, let petLayer else { t.invalidate(); return }
                f = (f + 1) % frames.count
                CATransaction.begin(); CATransaction.setDisableActions(true)
                petLayer.contents = frames[f]
                CATransaction.commit()
            }
        }
        let jar = NSTextField(labelWithString: "bug jar \(g.bugJar) \u{00B7} \(g.guestbook.count) visits \u{00B7} click a piece to put it away")
        jar.font = .systemFont(ofSize: 10)
        jar.textColor = NSColor(white: 1, alpha: 0.5)
        jar.frame = NSRect(x: 14, y: 6, width: size.width - 28, height: 14)
        addSubview(jar)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let hit = layer?.sublayers?.last(where: { $0.name != nil && $0.frame.contains(p) }), let id = hit.name else { return }
        backend.growth.toggleFurniture(id)
        Feel.haptic(.tick)
        backend.live.lastKey = ""
        backend.live.refreshContent(clear: true)
    }
}

// MARK: - Settings rows: privacy ledger, stream mode, visits, focus

extension Backend {
    func privacyControls() -> [NSView] {
        var v: [NSView] = [caption("Privacy ledger")]
        let rows = [("Code, prompts, diffs", "never read"), ("Screen contents", "never read"), ("File paths, repo names", "stay on this Mac"),
                    ("Tool names and counts", "only for the diary, if on"), ("Impression counts", "a signed number per campaign"),
                    ("Identity", "one anonymous proof of personhood")]
        for (k, val) in rows { v.append(row(k, val)) }
        v.append(label("Always on: pets duck when the screen is shared or recorded, sleep in meetings, hide in full screen. \u{2325}\u{2318}P pauses everything.", 11, .regular, .secondaryLabelColor))
        v.append(NSStackView(views: [NSButton(title: "Export my data\u{2026}", target: self, action: #selector(exportData)),
                                     NSButton(title: "Delete my data\u{2026}", target: self, action: #selector(deleteData))]))
        let stream = NSButton(checkboxWithTitle: "Stream mode (OBS overlay on 127.0.0.1:\(StreamServer.port)/overlay; lines off)", target: self, action: #selector(toggleStream(_:)))
        stream.state = PrivacyController.streamOn ? .on : .off
        let visits = NSButton(checkboxWithTitle: "Allow visits from other pets (guestbook)", target: self, action: #selector(toggleVisits(_:)))
        visits.state = PrivacyController.visitsOn ? .on : .off
        let focus = NSSegmentedControl(labels: FocusSession.durations.map { "Focus \($0)m" }, trackingMode: .momentary, target: self, action: #selector(startFocus(_:)))
        return v + [stream, visits, caption("Focus (\u{2325}\u{2318}F starts 25 min; lines off, no earning)"), focus]
    }
    @objc func exportData() { privacy.export() }
    @objc func deleteData() { privacy.deleteAll() }
    @objc func toggleStream(_ b: NSButton) { privacy.setStream(b.state == .on) }
    @objc func toggleVisits(_ b: NSButton) { defaults.set(b.state == .on, forKey: "visits") }
    @objc func startFocus(_ s: NSSegmentedControl) {
        if privacy.focus != nil { privacy.endFocus(finished: false) }
        privacy.toggleFocus(FocusSession.durations[max(0, s.selectedSegment)])
    }
    @objc func endFocusNow() { privacy.endFocus(finished: false) }
    @objc func openRoom() { live.roomOpen = true; live.update() }
    @objc func makePostcardNow() { privacy.makePostcard() }
    @objc func savePostcard() {
        guard let src = privacy.latestPostcard else { return }
        let p = NSSavePanel(); p.nameFieldStringValue = src.lastPathComponent
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK, let url = p.url { try? FileManager.default.copyItem(at: src, to: url) }
    }
    @objc func copyPostcard() {
        guard let src = privacy.latestPostcard, let img = NSImage(contentsOf: src) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
    }
    @objc func roomTake(_ b: ItemButton) { growth.takeFurniture(b.item); rebuildGrowth() }
}
