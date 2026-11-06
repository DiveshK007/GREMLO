import AppKit
import Network

// Sheet layout comes from Resources/rows.json: 192x208 cells, 8 columns, 9 rows.
let cellSize = CGSize(width: 192, height: 208)
let sheetCols = 8, sheetRows = 9
// One art pixel is 7 sheet pixels; draw it at 2 points.
let drawScale: CGFloat = 2.0 / 7.0
// Empty sheet pixels under the feet (cell height 208, baseline 190).
let footPadding = (208.0 - 190.0) * drawScale

enum PetState: String { case greet, walk, idle, sign, flag, celebrate, fail }

struct Anim { let row: Int; let frames: [Int]; let loops: Bool }

let anims: [PetState: Anim] = [
    .greet: Anim(row: 3, frames: [0, 1, 2, 3], loops: false),
    .walk: Anim(row: 1, frames: Array(0..<8), loops: true),
    .idle: Anim(row: 5, frames: [0, 0, 1, 1, 0, 0, 2, 0], loops: true),
    .sign: Anim(row: 6, frames: Array(0..<6), loops: true),
    .flag: Anim(row: 7, frames: Array(0..<6), loops: true),
    .celebrate: Anim(row: 4, frames: Array(0..<5) + Array(0..<5), loops: false),
    .fail: Anim(row: 8, frames: Array(0..<6), loops: false),
]

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

final class Pet {
    let frames: [[CGImage]]
    let panel: NSPanel
    let sprite = CALayer()
    let size = CGSize(width: cellSize.width * drawScale, height: cellSize.height * drawScale)
    var state = PetState.greet
    var next = PetState.walk
    var frame = 0
    var x: CGFloat = 0
    var dir: CGFloat = 1

    init(frames: [[CGImage]]) {
        self.frames = frames
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        sprite.frame = view.bounds
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.contentsGravity = .resizeAspect
        view.layer?.addSublayer(sprite)
        panel.contentView = view

        let screen = NSScreen.main?.visibleFrame ?? .zero
        x = screen.midX - size.width / 2
        place()
        panel.orderFrontRegardless()
        set(.greet, then: .walk)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    func set(_ s: PetState, then after: PetState? = nil) {
        if s != state { print("state \(state.rawValue) -> \(s.rawValue)") }
        state = s
        next = after ?? s
        frame = 0
        draw()
    }

    func tick() {
        guard let anim = anims[state] else { return }
        frame += 1
        if frame >= anim.frames.count {
            if anim.loops { frame = 0 } else { set(next); return }
        }
        if state == .walk { walk() }
        draw()
    }

    func walk() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        x += dir * 3
        if x < screen.minX { x = screen.minX; dir = 1 }
        if x > screen.maxX - size.width { x = screen.maxX - size.width; dir = -1 }
        place()
    }

    func place() {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: x, y: screen.minY - footPadding))
    }

    func draw() {
        guard let anim = anims[state] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = frames[anim.row][anim.frames[frame]]
        sprite.setAffineTransform(state == .walk && dir < 0 ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
        CATransaction.commit()
    }

    // Maps a Claude Code hook event to a pet state. See CLAUDE.md, "Pet state machine".
    func handle(event: String, notification: String?) {
        switch event {
        case "SessionStart": set(.greet, then: .walk)
        case "UserPromptSubmit": set(.greet, then: .sign)
        case "PreToolUse", "PostToolUse":
            if state == .greet { next = .sign } else if state != .sign { set(.sign) }
        case "PermissionRequest": set(.flag)
        case "Notification":
            if notification == "permission_prompt" { set(.flag) }
            else if notification == "idle_prompt" { set(.idle) }
        case "Stop": set(.celebrate, then: .walk)
        case "StopFailure": set(.fail, then: .idle)
        case "SessionEnd": set(.idle)
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
            if case .failed(let err) = state { print("hook server failed: \(err)"); exit(1) }
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
let pet = Pet(frames: frames)
let server: HookServer
do {
    server = try HookServer(port: 47474) { event, notification in
        pet.handle(event: event, notification: notification)
    }
} catch {
    print("cannot listen on 47474: \(error)")
    exit(1)
}
print("Notchi running, hooks on 127.0.0.1:47474")
app.run()
