import AppKit
import Network

let tickHz = 30.0
// Seconds of quiet after the agent stops before the pet climbs home. Override with NOTCHI_HOME_AFTER.
let homeAfter = TimeInterval(ProcessInfo.processInfo.environment["NOTCHI_HOME_AFTER"] ?? "") ?? 75

enum PetState: String, CaseIterable { case greet, walk, idle, sign, flag, celebrate, fail, climb, eat }

let loopingStates: Set<PetState> = [.walk, .climb, .idle, .sign, .flag]

// Frame order within a state's strip of n frames.
func sequence(_ s: PetState, _ n: Int) -> [Int] {
    switch s {
    case .idle where n >= 3: return [0, 0, 1, 1, 0, 0, 2, 0]
    case .celebrate: return Array(0..<n) + Array(0..<n)
    default: return Array(0..<n)
    }
}

// Where the pet is, separate from what it is doing.
enum Path: String { case home, falling, floor, toWall, climbing, ceiling, entering }

// A pet folder: <state>.png horizontal strips plus pet.json, e.g. assets/pets/mochi/.
struct SkinInfo: Decodable {
    let fps: Double
    let frames: [String: Int]
    let pixel: Double     // strip pixels per art pixel; one art pixel draws at 2 points
    let baseline: Double  // strip row the feet stand on
}

struct Skin {
    let name: String
    let fps: Double
    let size: CGSize
    let footPadding: CGFloat
    let strips: [PetState: [CGImage]]
}

// assets/demo-pets/ (gitignored) wins over assets/pets/ when it exists. NOTCHI_SKIN picks a folder by name, else the first one.
func loadSkin() -> Skin? {
    let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("assets")
    let fm = FileManager.default
    let demo = assets.appendingPathComponent("demo-pets")
    let root = fm.fileExists(atPath: demo.path) ? demo : assets.appendingPathComponent("pets")
    let names = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    guard let name = ProcessInfo.processInfo.environment["NOTCHI_SKIN"] ?? names.first else {
        print("no pet folders in \(root.path)")
        return nil
    }
    let dir = root.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("pet.json")),
          let info = try? JSONDecoder().decode(SkinInfo.self, from: data) else {
        print("\(dir.path)/pet.json missing or invalid")
        return nil
    }
    var strips: [PetState: [CGImage]] = [:]
    var cell = CGSize.zero
    for s in PetState.allCases {
        guard let n = info.frames[s.rawValue], n > 0,
              let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(s.rawValue + ".png") as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
        let w = img.width / n
        strips[s] = (0..<n).compactMap { img.cropping(to: CGRect(x: $0 * w, y: 0, width: w, height: img.height)) }
        cell = CGSize(width: w, height: img.height)
    }
    guard strips[.walk] != nil else {
        print("\(dir.path) has no walk.png")
        return nil
    }
    for s in PetState.allCases where strips[s] == nil { print("\(name): no \(s.rawValue) strip, using walk") }
    let scale = 2 / info.pixel
    print("pet skin \(dir.path)")
    return Skin(name: name, fps: info.fps, size: CGSize(width: cell.width * scale, height: cell.height * scale),
                footPadding: (cell.height - info.baseline) * scale, strips: strips)
}

// The screen with the menu bar (and the notch, if there is one).
var mainScreen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

func overlayPanel(_ size: CGSize, level: NSWindow.Level) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = level
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    let view = NSView(frame: NSRect(origin: .zero, size: size))
    view.wantsLayer = true
    panel.contentView = view
    return panel
}

enum DoorState: String { case closed, glowing, open, locked }

// A small arched door hanging under the notch. Drawn in code until there is door art.
final class Door {
    let size = CGSize(width: 16, height: 20)
    let panel: NSPanel
    let arch = CAShapeLayer()
    let lockBody = CAShapeLayer()
    let lockShackle = CAShapeLayer()
    let amber = CGColor(red: 0.95, green: 0.72, blue: 0.29, alpha: 1)
    let brown = CGColor(red: 0.23, green: 0.18, blue: 0.15, alpha: 1)
    var state = DoorState.closed

    init() {
        panel = overlayPanel(size, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: size.width - 1, y: 1))
        path.addLine(to: CGPoint(x: size.width - 1, y: size.height - size.width / 2))
        path.addArc(center: CGPoint(x: size.width / 2, y: size.height - size.width / 2),
                    radius: size.width / 2 - 1, startAngle: 0, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        arch.path = path
        arch.lineWidth = 1
        lockBody.path = CGPath(rect: CGRect(x: 5, y: 4, width: 6, height: 5), transform: nil)
        let shackle = CGMutablePath()
        shackle.addArc(center: CGPoint(x: 8, y: 9), radius: 2, startAngle: 0, endAngle: .pi, clockwise: false)
        lockShackle.path = shackle
        lockShackle.fillColor = nil
        lockShackle.lineWidth = 1
        for layer in [arch, lockBody, lockShackle] { panel.contentView?.layer?.addSublayer(layer) }
        place()
        set(.closed)
        panel.orderFrontRegardless()
    }

    // Bottom centre of the notch; top centre under the menu bar on Macs without one.
    func place() {
        let screen = mainScreen
        var midX = screen.frame.midX
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            midX = (left.maxX + right.minX) / 2
        }
        panel.setFrameOrigin(NSPoint(x: midX - size.width / 2, y: screen.visibleFrame.maxY - size.height))
    }

    var center: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    func set(_ s: DoorState) {
        if s != state { print("door \(state.rawValue) -> \(s.rawValue)") }
        state = s
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arch.fillColor = s == .open ? amber : CGColor(gray: 0, alpha: 1)
        arch.strokeColor = s == .glowing ? amber : brown
        arch.shadowColor = amber
        arch.shadowRadius = 4
        arch.shadowOffset = .zero
        arch.shadowOpacity = s == .glowing ? 0.9 : 0
        lockBody.fillColor = amber
        lockShackle.strokeColor = amber
        lockBody.isHidden = s != .locked
        lockShackle.isHidden = s != .locked
        CATransaction.commit()
    }
}

final class Pet {
    let skin: Skin
    let door: Door
    let panel: NSPanel
    let sprite = CALayer()
    var size: CGSize { skin.size }
    var state = PetState.walk
    var next = PetState.walk
    var frame = 0
    var animClock = 0.0
    var path = Path.home
    var pos = CGPoint.zero
    var vy: CGFloat = 0
    var dir: CGFloat = 1
    var shrink: CGFloat = 1
    var afterLanding = PetState.walk
    var lastActive = Date()
    var sessionLive = false
    var lockWhenHome = false
    // The sponsored line, from GET /campaigns/active. Shown above the pet while it holds the sign.
    let signPanel = overlayPanel(CGSize(width: 10, height: 20), level: .statusBar)
    let signLabel = NSTextField(labelWithString: "")
    // Short speech bubble ("+0.005 0G"). Above the pet, or under the door while it is home.
    let bubblePanel = overlayPanel(CGSize(width: 10, height: 20), level: .statusBar)
    let bubbleLabel = NSTextField(labelWithString: "")
    var bubbleUntil = Date.distantPast

    var floorY: CGFloat { mainScreen.visibleFrame.minY - skin.footPadding }
    var topY: CGFloat { mainScreen.visibleFrame.maxY - size.height }
    var leftX: CGFloat { mainScreen.visibleFrame.minX }
    var rightX: CGFloat { mainScreen.visibleFrame.maxX - size.width }
    var doorX: CGFloat { door.center.x - size.width / 2 }

    init(skin: Skin, door: Door) {
        self.skin = skin
        self.door = door
        panel = overlayPanel(skin.size, level: .statusBar)
        sprite.frame = CGRect(origin: .zero, size: size)
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.contentsGravity = .resizeAspect
        panel.contentView?.layer?.addSublayer(sprite)
        signLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        signLabel.textColor = .black
        signLabel.drawsBackground = true
        signLabel.backgroundColor = NSColor(red: 0.98, green: 0.93, blue: 0.80, alpha: 1)
        signPanel.contentView?.addSubview(signLabel)
        bubbleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        bubbleLabel.textColor = .black
        bubbleLabel.drawsBackground = true
        bubbleLabel.backgroundColor = .white
        bubblePanel.contentView?.addSubview(bubbleLabel)
        Timer.scheduledTimer(withTimeInterval: 1 / tickHz, repeats: true) { [weak self] _ in self?.tick() }
    }

    func go(_ p: Path) {
        if p != path { print("path \(path.rawValue) -> \(p.rawValue)") }
        path = p
    }

    func set(_ s: PetState, then after: PetState? = nil) {
        if s != state { print("state \(state.rawValue) -> \(s.rawValue)") }
        state = s
        next = after ?? s
        frame = 0
        animClock = 0
    }

    // Leave the house (or drop off the wall) and land on the floor, then show `s`.
    func comeOut(then s: PetState) {
        lastActive = Date()
        afterLanding = s
        switch path {
        case .floor:
            set(s)
            return
        case .falling:
            return
        case .home:
            door.set(.open)
            pos = CGPoint(x: doorX, y: door.panel.frame.minY - size.height + 8)
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.path != .home else { return }
                self.door.set(self.sessionLive ? .glowing : .closed)
            }
        case .toWall, .climbing, .ceiling, .entering:
            break
        }
        lockWhenHome = false
        shrink = 1
        vy = 0
        set(.greet)
        go(.falling)
    }

    func goHome(lock: Bool) {
        lockWhenHome = lock
        switch path {
        case .home: if lock { door.set(.locked) }
        case .floor:
            dir = 1
            set(.walk)
            go(.toWall)
        default: break
        }
    }

    func tick() {
        let dt = 1 / tickHz
        switch path {
        case .home:
            placeBubble()
            return
        case .falling:
            vy += 2400 * dt
            pos.y -= vy * dt
            if pos.y <= floorY {
                pos.y = floorY
                go(.floor)
                set(.greet, then: afterLanding)
            }
        case .floor:
            if state == .walk {
                pos.x += dir * 24 * dt
                if pos.x < leftX { pos.x = leftX; dir = 1 }
                if pos.x > rightX { pos.x = rightX; dir = -1 }
            }
            if state == .walk || state == .idle, Date().timeIntervalSince(lastActive) > homeAfter {
                goHome(lock: false)
            }
        case .toWall:
            pos.x += 140 * dt
            if pos.x >= rightX { pos.x = rightX; set(.climb); go(.climbing) }
        case .climbing:
            pos.y += 140 * dt
            if pos.y >= topY { pos.y = topY; dir = -1; set(.walk); go(.ceiling) }
        case .ceiling:
            pos.x -= 140 * dt
            if pos.x <= doorX { pos.x = doorX; door.set(.open); go(.entering) }
        case .entering:
            shrink -= 2.5 * dt
            if shrink <= 0 {
                shrink = 1
                panel.orderOut(nil)
                go(.home)
                door.set(lockWhenHome ? .locked : (sessionLive ? .glowing : .closed))
                return
            }
        }
        animClock += skin.fps * dt
        while animClock >= 1 {
            animClock -= 1
            advanceFrame()
        }
        panel.setFrameOrigin(NSPoint(x: pos.x, y: pos.y))
        draw()
        placeSign()
        placeBubble()
    }

    func say(_ text: String, for seconds: TimeInterval) {
        bubbleLabel.stringValue = text
        bubbleLabel.sizeToFit()
        bubblePanel.setContentSize(bubbleLabel.frame.size)
        bubbleUntil = Date().addingTimeInterval(seconds)
        placeBubble()
    }

    // Money landed in the wallet: play eat (on screen only) and show the amount.
    func eat(_ amount: String) {
        say(amount, for: 4)
        if path == .floor && state != .eat { set(.eat, then: next) }
    }

    func placeBubble() {
        if Date() >= bubbleUntil { if bubblePanel.isVisible { bubblePanel.orderOut(nil) }; return }
        let w = bubblePanel.frame.width, h = bubblePanel.frame.height
        var x = pos.x + size.width / 2 - w / 2
        var y = pos.y + size.height - 6 + (signPanel.isVisible ? signPanel.frame.height + 2 : 0)
        if path == .home { x = door.center.x - w / 2; y = door.panel.frame.minY - h - 2 }
        x = min(max(x, leftX), mainScreen.visibleFrame.maxX - w)
        bubblePanel.setFrameOrigin(NSPoint(x: x, y: min(y, mainScreen.visibleFrame.maxY - h)))
        if !bubblePanel.isVisible { bubblePanel.orderFrontRegardless() }
    }

    func setSign(_ text: String?) {
        signLabel.stringValue = text ?? ""
        signLabel.sizeToFit()
        signPanel.setContentSize(signLabel.frame.size)
    }

    func placeSign() {
        let show = path == .floor && state == .sign && !signLabel.stringValue.isEmpty
        if !show { if signPanel.isVisible { signPanel.orderOut(nil) }; return }
        let w = signPanel.frame.width
        let x = min(max(pos.x + size.width / 2 - w / 2, leftX), mainScreen.visibleFrame.maxX - w)
        signPanel.setFrameOrigin(NSPoint(x: x, y: pos.y + size.height - 6))
        if !signPanel.isVisible { signPanel.orderFrontRegardless() }
    }

    func advanceFrame() {
        if path == .falling { return }  // hold the first greet frame mid-air
        frame += 1
        if frame >= sequence(state, strip.count).count {
            if loopingStates.contains(state) { frame = 0 } else { set(next) }
        }
    }

    var strip: [CGImage] { skin.strips[state] ?? skin.strips[.walk]! }

    func draw() {
        var t = CGAffineTransform.identity
        if state == .walk && dir < 0 { t = t.scaledBy(x: -1, y: 1) }
        // Climb frames face left; mirror them so the feet are on the right wall.
        if state == .climb { t = t.scaledBy(x: -1, y: 1) }
        if path == .entering {
            // Shrink towards the top centre, into the door.
            t = CGAffineTransform(translationX: 0, y: size.height / 2 * (1 - shrink)).scaledBy(x: shrink, y: shrink)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = strip[sequence(state, strip.count)[frame]]
        sprite.setAffineTransform(t)
        CATransaction.commit()
    }

    // Maps a Claude Code hook event to the pet. See CLAUDE.md, "Pet state machine".
    func handle(event: String, notification: String?) {
        switch event {
        case "SessionStart":
            sessionLive = true
            if path == .home { door.set(.glowing) }
        case "UserPromptSubmit":
            sessionLive = true
            if path == .floor { lastActive = Date(); set(.greet, then: .sign) } else { comeOut(then: .sign) }
        case "PreToolUse", "PostToolUse":
            lastActive = Date()
            if path != .floor { comeOut(then: .sign) }
            else if state == .greet { next = .sign }
            else if state != .sign { set(.sign) }
        case "PermissionRequest":
            comeOut(then: .flag)
        case "Notification":
            if notification == "permission_prompt" { comeOut(then: .flag) }
            else if notification == "idle_prompt", path == .floor { set(.idle) }
        case "Stop":
            lastActive = Date()
            if path == .floor { set(.celebrate, then: .walk) }
        case "StopFailure":
            lastActive = Date()
            if path == .floor { set(.fail, then: .idle) }
        case "SessionEnd":
            sessionLive = false
            goHome(lock: true)
        default: break
        }
    }
}

// Minimal HTTP listener for the hooks. Replies 200 with an empty body at once, never a decision.
final class HookServer {
    let listener: NWListener
    let onEvent: ([String: Any]) -> Void

    init(port: UInt16, onEvent: @escaping ([String: Any]) -> Void) throws {
        self.onEvent = onEvent
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.read(conn, Data())
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                if case .posix(.EADDRINUSE) = err {
                    print("Port 47474 is taken: Notchi is probably already running. Stop it with: pkill -x Notchi")
                } else {
                    print("hook server failed: \(err)")
                }
                exit(1)
            }
        }
        listener.start(queue: .main)
    }

    func read(_ conn: NWConnection, _ buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self).lowercased()
                let length = head.split(separator: "\r\n")
                    .first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buf[end.upperBound...]
                if body.count >= length || done || err != nil {
                    self.finish(conn, body: Data(body.prefix(length)))
                    return
                }
            }
            if done || err != nil || buf.count > 8_000_000 { conn.cancel(); return }
            self.read(conn, buf)
        }
    }

    func finish(_ conn: NWConnection, body: Data) {
        let reply = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() })
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              json["hook_event_name"] is String else { return }
        onEvent(json)
    }
}

struct Campaign: Decodable { let campaignId: String; let line: String?; let brand: String; let ratePerImpression: String }
struct Thought: Decodable { let action: String; let requestId: String; let at: Int }
struct Meal: Decodable { let amount: String; let txHash: String; let at: Int }
struct PetInfo: Decodable {
    let name: String; let mood: String; let walletBalance: String?; let computeBalance: String?
    let impressionsToday: Int; let lastThoughts: [Thought]; let lastMeal: Meal?; let seeded: Bool
}
struct ThinkResult: Decodable { let action: String; let say: String?; let reason: String?; let requestId: String? }

func og(_ wei: String?) -> String {
    guard let wei, let d = Decimal(string: wei) else { return "unknown" }
    return og(d)
}

func og(_ wei: Decimal) -> String { "\(wei / Decimal(sign: .plus, exponent: 18, significand: 1)) 0G" }

// "+0.005 0G" when the wei balance went up, nil otherwise (first poll, unknown, same or down).
func ogGain(_ old: String?, _ new: String?) -> String? {
    guard let o = old.flatMap({ Decimal(string: $0) }), let n = new.flatMap({ Decimal(string: $0) }), n > o else { return nil }
    return "+" + og(n - o)
}

// Talks to apps/server. Server down means the popover says so; nothing is invented.
final class Backend: NSObject {
    let base = ProcessInfo.processInfo.environment["NOTCHI_SERVER"] ?? "http://localhost:8787"
    let petName = ProcessInfo.processInfo.environment["NOTCHI_PET"] ?? "mochi.notchi.eth"
    let pet: Pet
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    let text = NSTextField(wrappingLabelWithString: "loading")
    var campaign: Campaign?
    var info: PetInfo?
    var lastThink = "no think yet"
    var serverError: String?
    var thinking = false

    init(pet: Pet) {
        self.pet = pet
        super.init()
        item.button?.title = "Notchi"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.preferredMaxLayoutWidth = 360
        let vc = NSViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 220))
        text.frame = vc.view.bounds.insetBy(dx: 10, dy: 10)
        text.autoresizingMask = [.width, .height]
        vc.view.addSubview(text)
        popover.contentViewController = vc
        popover.behavior = .transient
        refresh()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc func toggle() {
        if popover.isShown { popover.close() } else if let b = item.button { popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY) }
    }

    var petPath: String { "/pets/" + (petName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? petName) }

    func request(_ path: String, body: [String: Any]? = nil, done: @escaping (Data?, String?) -> Void) {
        var req = URLRequest(url: URL(string: base + path)!, timeoutInterval: 30)
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
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
            if let data { self.campaign = try? JSONDecoder().decode(Campaign?.self, from: data) }
            self.render()
        }
        request(petPath) { data, err in
            if let err { self.serverError = "pet \(self.petName): \(err)" }
            if let data, let new = try? JSONDecoder().decode(PetInfo.self, from: data) {
                if let gain = ogGain(self.info?.walletBalance, new.walletBalance) { self.pet.eat(gain + (new.seeded ? " [seeded]" : "")) }
                self.info = new
            }
            self.render()
        }
    }

    // One think in flight at a time; events during a pending call are skipped so a tool burst can't stack paid calls.
    func think(_ hook: [String: Any]) {
        guard !thinking else { return }
        thinking = true
        let body: [String: Any] = ["event": hook["hook_event_name"] ?? "", "sessionId": hook["session_id"] ?? "",
                                   "toolName": hook["tool_name"] ?? "", "notificationType": hook["notification_type"] ?? ""]
        request(petPath + "/think", body: body) { data, err in
            self.thinking = false
            if let err { self.lastThink = "think failed: \(err)" }
            else if let data, let r = try? JSONDecoder().decode(ThinkResult.self, from: data) {
                let id = r.requestId.map { "request \($0)" } ?? "no request ID"
                self.lastThink = r.action == "sleep" ? "sleep: \(r.reason ?? "") (\(id))" : "\(r.action) \"\(r.say ?? "")\" (\(id))"
            }
            self.refresh()
        }
    }

    func render() {
        let seeded = info?.seeded ?? false
        let tag = seeded ? " [seeded]" : ""
        pet.setSign(campaign?.line.map { $0 + tag })
        var lines: [String] = []
        if seeded { lines.append("SEEDED DATA: not real 0G tokens") }
        if let e = serverError { lines.append("server: \(e)") }
        if let i = info {
            lines.append("\(i.name)  mood: \(i.mood)")
            lines.append("wallet: \(og(i.walletBalance))\(tag)   compute: \(og(i.computeBalance))")
            lines.append("impressions today: \(i.impressionsToday)\(tag)")
            lines.append("last meal: " + (i.lastMeal.map { "\(og($0.amount)) tx \($0.txHash)" } ?? "none"))
        }
        lines.append("sign: " + (campaign.map { "\"\($0.line ?? "(line unknown)")\" by \($0.brand)\(tag)" } ?? "no active campaign"))
        lines.append("last think: \(lastThink)")
        for t in info?.lastThoughts.prefix(5) ?? [] { lines.append("  \(t.action)  request \(t.requestId)") }
        text.stringValue = lines.joined(separator: "\n")
    }
}

assert(ogGain("1000000000000000000", "1005000000000000000") == "+0.005 0G")
assert(ogGain("123456789012345678901", "123456789012345678902") == "+0.000000000000000001 0G")
assert(ogGain("5", "5") == nil && ogGain("5", "4") == nil && ogGain(nil, "5") == nil)
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let skin = loadSkin() else { exit(1) }
let door = Door()
let pet = Pet(skin: skin, door: door)
let backend = Backend(pet: pet)
let server: HookServer
do {
    server = try HookServer(port: 47474) { hook in
        pet.handle(event: hook["hook_event_name"] as! String, notification: hook["notification_type"] as? String)
        backend.think(hook)
    }
} catch {
    print("cannot listen on 47474: \(error)")
    exit(1)
}
print("Notchi running, hooks on 127.0.0.1:47474, home after \(Int(homeAfter))s")
app.run()
