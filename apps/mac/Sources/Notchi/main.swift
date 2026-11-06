import AppKit
import Network

// Sheet layout comes from Resources/rows.json: 192x208 cells, 8 columns, 9 rows.
let cellSize = CGSize(width: 192, height: 208)
let sheetCols = 8, sheetRows = 9
// One art pixel is 7 sheet pixels; draw it at 2 points.
let drawScale: CGFloat = 2.0 / 7.0
// Empty sheet pixels under the feet (cell height 208, baseline 190).
let footPadding = (208.0 - 190.0) * drawScale
let tickHz = 30.0
let animFps = 8.0
// Seconds of quiet after the agent stops before the pet climbs home. Override with NOTCHI_HOME_AFTER.
let homeAfter = TimeInterval(ProcessInfo.processInfo.environment["NOTCHI_HOME_AFTER"] ?? "") ?? 75

enum PetState: String { case greet, walk, idle, sign, flag, celebrate, fail, climb }

struct Anim { let row: Int; let frames: [Int]; let loops: Bool }

let anims: [PetState: Anim] = [
    .greet: Anim(row: 3, frames: [0, 1, 2, 3], loops: false),
    .walk: Anim(row: 1, frames: Array(0..<8), loops: true),
    .climb: Anim(row: 2, frames: Array(0..<8), loops: true),
    .idle: Anim(row: 5, frames: [0, 0, 1, 1, 0, 0, 2, 0], loops: true),
    .sign: Anim(row: 6, frames: Array(0..<6), loops: true),
    .flag: Anim(row: 7, frames: Array(0..<6), loops: true),
    .celebrate: Anim(row: 4, frames: Array(0..<5) + Array(0..<5), loops: false),
    .fail: Anim(row: 8, frames: Array(0..<6), loops: false),
]

// Where the pet is, separate from what it is doing.
enum Path: String { case home, falling, floor, toWall, climbing, ceiling, entering }

func loadFrames(_ url: URL) -> [[CGImage]]? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return (0..<sheetRows).map { r in
        (0..<sheetCols).compactMap { c in
            img.cropping(to: CGRect(x: CGFloat(c) * cellSize.width, y: CGFloat(r) * cellSize.height,
                                    width: cellSize.width, height: cellSize.height))
        }
    }
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
    let frames: [[CGImage]]
    let door: Door
    let panel: NSPanel
    let sprite = CALayer()
    let size = CGSize(width: cellSize.width * drawScale, height: cellSize.height * drawScale)
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

    var floorY: CGFloat { mainScreen.visibleFrame.minY - footPadding }
    var topY: CGFloat { mainScreen.visibleFrame.maxY - size.height }
    var leftX: CGFloat { mainScreen.visibleFrame.minX }
    var rightX: CGFloat { mainScreen.visibleFrame.maxX - size.width }
    var doorX: CGFloat { door.center.x - size.width / 2 }

    init(frames: [[CGImage]], door: Door) {
        self.frames = frames
        self.door = door
        panel = overlayPanel(size, level: .statusBar)
        sprite.frame = CGRect(origin: .zero, size: size)
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.contentsGravity = .resizeAspect
        panel.contentView?.layer?.addSublayer(sprite)
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
        animClock += animFps * dt
        while animClock >= 1 {
            animClock -= 1
            advanceFrame()
        }
        panel.setFrameOrigin(NSPoint(x: pos.x, y: pos.y))
        draw()
    }

    func advanceFrame() {
        if path == .falling { return }  // hold the first greet frame mid-air
        guard let anim = anims[state] else { return }
        frame += 1
        if frame >= anim.frames.count {
            if anim.loops { frame = 0 } else { set(next) }
        }
    }

    func draw() {
        guard let anim = anims[state] else { return }
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
        sprite.contents = frames[anim.row][anim.frames[frame]]
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
    let onEvent: (String, String?) -> Void

    init(port: UInt16, onEvent: @escaping (String, String?) -> Void) throws {
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
              let event = json["hook_event_name"] as? String else { return }
        onEvent(event, json["notification_type"] as? String)
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let url = Bundle.module.url(forResource: "spritesheet", withExtension: "webp"),
      let frames = loadFrames(url) else {
    print("spritesheet missing or unreadable")
    exit(1)
}
let door = Door()
let pet = Pet(frames: frames, door: door)
let server: HookServer
do {
    server = try HookServer(port: 47474) { event, notification in
        pet.handle(event: event, notification: notification)
    }
} catch {
    print("cannot listen on 47474: \(error)")
    exit(1)
}
print("Notchi running, hooks on 127.0.0.1:47474, home after \(Int(homeAfter))s")
app.run()
