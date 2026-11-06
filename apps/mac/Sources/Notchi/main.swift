import AppKit
import Network

let tickHz = 30.0
// Seconds of quiet after the agent stops before the pet climbs home. Override with NOTCHI_HOME_AFTER.
let homeAfter = TimeInterval(ProcessInfo.processInfo.environment["NOTCHI_HOME_AFTER"] ?? "") ?? 75

enum PetState: String, CaseIterable { case greet, walk, idle, sign, flag, celebrate, fail, climb, eat, hover, annoy }

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

// Two pet folder formats, see assets/pets/README.md:
// strips: <state>.png + pet.json with frames/fps/pixel/baseline (mochi)
// sheet:  spritesheet.webp + pet.json (Codex pet format), rows from rows.json in the folder or assets/pets/notchi-rows.json
struct SkinInfo: Decodable {
    let fps: Double?
    let frames: [String: Int]?
    let pixel: Double?     // strip pixels per art pixel; one art pixel draws at 2 points
    let baseline: Double?  // strip row the feet stand on
    let spritesheetPath: String?
}

struct RowMap: Decodable {
    struct Row: Decodable { let row: Int; let name: String; let frames: Int }
    let cell: [Int]
    let baseline: Double
    let scale: Double
    let rows_map: [Row]
    let fps: [String: Double]?
}

struct Skin {
    let name: String
    let fps: Double
    let fpsByMood: [String: Double]
    let size: CGSize
    let footPadding: CGFloat
    let strips: [PetState: [CGImage]]
    let doors: [DoorState: CGImage]  // empty unless all four door_<state>.png exist
    let scale: CGFloat               // points per sheet pixel
}

let assetsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("assets")
let defaultSkin = "notchi-ink"

// Every folder with a pet.json in assets/demo-pets (gitignored) and assets/pets, demo first.
func petFolders() -> [(name: String, dir: URL)] {
    ["demo-pets", "pets"].flatMap { sub -> [(name: String, dir: URL)] in
        let root = assetsDir.appendingPathComponent(sub)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        return names.map { (name: $0, dir: root.appendingPathComponent($0)) }
            .filter { FileManager.default.fileExists(atPath: $0.dir.appendingPathComponent("pet.json").path) }
    }
}

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// Loads `want` (or NOTCHI_SKIN, or notchi-ink); falls back to the first pet that loads.
func loadSkin(_ want: String? = nil) -> Skin? {
    let folders = petFolders()
    let pick = want ?? ProcessInfo.processInfo.environment["NOTCHI_SKIN"] ?? defaultSkin
    let ordered = folders.filter { $0.name == pick } + folders.filter { $0.name != pick }
    for f in ordered {
        if let skin = loadSkin(name: f.name, dir: f.dir) { return skin }
    }
    print("no loadable pet in \(assetsDir.path)/demo-pets or /pets")
    return nil
}

func loadSkin(name: String, dir: URL) -> Skin? {
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("pet.json")),
          let info = try? JSONDecoder().decode(SkinInfo.self, from: data) else {
        print("\(dir.path)/pet.json missing or invalid")
        return nil
    }
    var strips: [PetState: [CGImage]] = [:]
    var cell = CGSize.zero
    var pixel = info.pixel ?? 7, baseline = info.baseline ?? 190, fps = info.fps ?? 8
    var fpsByMood: [String: Double] = [:]
    let sheetURL = dir.appendingPathComponent(info.spritesheetPath ?? "spritesheet.webp")
    if let sheet = loadImage(sheetURL) {
        let local = dir.appendingPathComponent("rows.json")
        let mapURL = FileManager.default.fileExists(atPath: local.path) ? local : assetsDir.appendingPathComponent("pets/notchi-rows.json")
        guard let mapData = try? Data(contentsOf: mapURL), let map = try? JSONDecoder().decode(RowMap.self, from: mapData),
              map.cell.count == 2 else {
            print("\(name): \(mapURL.path) missing or invalid")
            return nil
        }
        cell = CGSize(width: map.cell[0], height: map.cell[1])
        for row in map.rows_map {
            guard let s = PetState(rawValue: row.name) else { continue }
            let frames = (0..<row.frames).compactMap {
                sheet.cropping(to: CGRect(x: $0 * map.cell[0], y: row.row * map.cell[1], width: map.cell[0], height: map.cell[1]))
            }
            if frames.count == row.frames && row.frames > 0 { strips[s] = frames }
        }
        pixel = map.scale
        baseline = map.baseline
        fpsByMood = map.fps ?? [:]
        fps = fpsByMood["stable"] ?? fps
    } else {
        for s in PetState.allCases {
            guard let n = info.frames?[s.rawValue], n > 0,
                  let img = loadImage(dir.appendingPathComponent(s.rawValue + ".png")) else { continue }
            let w = img.width / n
            let frames = (0..<n).compactMap { img.cropping(to: CGRect(x: $0 * w, y: 0, width: w, height: img.height)) }
            guard w > 0, frames.count == n else { print("\(s.rawValue).png: \(n) frames don't fit \(img.width)px"); continue }
            strips[s] = frames
            cell = CGSize(width: w, height: img.height)
        }
    }
    guard strips[.walk] != nil else {
        print("\(dir.path) has no walk frames")
        return nil
    }
    for s in PetState.allCases where strips[s] == nil { print("\(name): no \(s.rawValue) frames, using walk") }
    let scale = 2 / pixel
    var doors: [DoorState: CGImage] = [:]
    for d in DoorState.allCases {
        if let img = loadImage(dir.appendingPathComponent("door_\(d.rawValue).png")) { doors[d] = img }
    }
    if !doors.isEmpty && doors.count < DoorState.allCases.count {
        print("\(name): door art needs all of door_closed/glowing/open/locked.png, drawing the default door")
        doors = [:]
    }
    print("pet skin \(dir.path)\(doors.isEmpty ? "" : " with door art")")
    return Skin(name: name, fps: fps, fpsByMood: fpsByMood, size: CGSize(width: cell.width * scale, height: cell.height * scale),
                footPadding: (cell.height - baseline) * scale, strips: strips, doors: doors, scale: scale)
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

enum DoorState: String, CaseIterable { case closed, glowing, open, locked }

// A hidden arched door under the notch. Invisible at rest so the notch looks stock; it only appears while
// the pet crosses: fade + scale in (55% to 100%), Signal glow, leaf swings open to the right, then closes and fades.
// Uses the pet's door_<state>.png art instead of the drawn leaf if it has all four.
final class Door {
    let size: CGSize
    let art: [DoorState: CGImage]
    let panel: NSPanel
    let body = CALayer()
    let glow = CAShapeLayer()
    let leaf = CAShapeLayer()
    let lockBody = CAShapeLayer()
    let lockShackle = CAShapeLayer()
    let artLayer = CALayer()
    let signal = CGColor(red: 1, green: 0x5A / 255.0, blue: 0x3C / 255.0, alpha: 1)
    let paper = CGColor(red: 0xF4 / 255.0, green: 0xF2 / 255.0, blue: 0xED / 255.0, alpha: 1)
    var state = DoorState.closed
    var gen = 0  // bumps on every open/close so a stale animation step can't reopen the door

    init(art: [DoorState: CGImage], scale: CGFloat) {
        self.art = art
        size = art[.closed].map { CGSize(width: CGFloat($0.width) * scale, height: CGFloat($0.height) * scale) } ?? CGSize(width: 14, height: 18)
        panel = overlayPanel(size, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        let bounds = CGRect(origin: .zero, size: size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: 0.5))
        path.addLine(to: CGPoint(x: size.width - 0.5, y: 0.5))
        path.addLine(to: CGPoint(x: size.width - 0.5, y: size.height - size.width / 2))
        path.addArc(center: CGPoint(x: size.width / 2, y: size.height - size.width / 2),
                    radius: size.width / 2 - 0.5, startAngle: 0, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        body.frame = bounds
        glow.frame = bounds
        glow.path = path
        glow.fillColor = signal
        glow.shadowColor = signal
        glow.shadowRadius = 5
        glow.shadowOffset = .zero
        glow.shadowOpacity = 1
        glow.opacity = 0
        leaf.anchorPoint = CGPoint(x: 1, y: 0.5)  // hinge on the right edge
        leaf.frame = bounds
        leaf.path = path
        leaf.fillColor = CGColor(gray: 0, alpha: 1)
        leaf.strokeColor = CGColor(gray: 1, alpha: 0.16)
        leaf.lineWidth = 1
        let mid = size.width / 2
        lockBody.path = CGPath(rect: CGRect(x: mid - 3, y: 4, width: 6, height: 5), transform: nil)
        lockBody.fillColor = paper
        let shackle = CGMutablePath()
        shackle.addArc(center: CGPoint(x: mid, y: 9), radius: 2, startAngle: 0, endAngle: .pi, clockwise: false)
        lockShackle.path = shackle
        lockShackle.fillColor = nil
        lockShackle.strokeColor = paper
        lockShackle.lineWidth = 1
        artLayer.frame = bounds
        artLayer.magnificationFilter = .nearest
        artLayer.contentsGravity = .resizeAspect
        let parts = art.isEmpty ? [glow, leaf, lockBody, lockShackle] : [artLayer]
        for layer in parts { body.addSublayer(layer) }
        panel.contentView?.layer?.addSublayer(body)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hide()
        showLock(false)
        CATransaction.commit()
        place()
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

    func log(_ s: DoorState) {
        if s != state { print("door \(state.rawValue) -> \(s.rawValue)") }
        state = s
    }

    func hide() {
        body.opacity = 0
        body.transform = CATransform3DMakeScale(0.55, 0.55, 1)
    }

    func showLock(_ on: Bool) {
        lockBody.isHidden = !on
        lockShackle.isHidden = !on
        if !art.isEmpty, on { artLayer.contents = art[.locked] }
    }

    // One eased step; `then` runs only if no newer open/close started meanwhile.
    func step(_ seconds: Double, _ g: Int, _ change: () -> Void, then: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(seconds)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self] in if self?.gen == g { then?() } }
        change()
        CATransaction.commit()
    }

    // Appear, glow, swing open. About 0.26s.
    func open() {
        gen += 1
        let g = gen
        log(.open)
        showLock(false)
        artLayer.contents = art[.closed]
        step(0.12, g, { body.opacity = 1; body.transform = CATransform3DIdentity }) {
            self.artLayer.contents = self.art[.glowing]
            self.step(0.06, g, { self.glow.opacity = 1 }) {
                self.artLayer.contents = self.art[.open]
                self.step(0.08, g, { self.leaf.transform = CATransform3DMakeScale(0.12, 1, 1) })
            }
        }
    }

    // Swing shut, show the padlock for a beat if locking, then fade and shrink away. About 0.14s, 0.5s with the lock.
    func close(lock: Bool) {
        gen += 1
        let g = gen
        log(lock ? .locked : .closed)
        artLayer.contents = art[.closed]
        step(0.08, g, { leaf.transform = CATransform3DIdentity; glow.opacity = 0; body.opacity = 1; body.transform = CATransform3DIdentity }) {
            self.showLock(lock)
            self.step(lock ? 0.35 : 0.0, g, {}) {
                self.step(0.12, g, { self.hide() }) { self.showLock(false) }
            }
        }
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
    var holdUntil = Date.distantPast
    // The sponsored line, from GET /campaigns/active. Shown above the pet while it holds the sign.
    let signPanel = overlayPanel(CGSize(width: 10, height: 20), level: .statusBar)
    let signLabel = NSTextField(labelWithString: "")
    var signShownAt: Date?
    // Short speech bubble ("+0.005 0G"). Above the pet, or under the door while it is home.
    let bubblePanel = overlayPanel(CGSize(width: 10, height: 20), level: .statusBar)
    let bubbleLabel = NSTextField(labelWithString: "")
    var bubbleUntil = Date.distantPast
    // From GET /pets/:name. Asleep keeps the pet home with sleepNote under the door.
    var mood = "stable"
    var sleepNote: String?
    var speed: Double { mood == "thriving" ? 1.4 : mood == "hungry" ? 0.6 : 1 }

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
        if mood == "asleep" { return }
        lastActive = Date()
        afterLanding = s
        switch path {
        case .floor:
            set(s)
            return
        case .falling:
            return
        case .home:
            // The pet drops once the door has swung open, then the door closes behind it.
            door.open()
            pos = CGPoint(x: doorX, y: door.panel.frame.minY - size.height + 8)
            holdUntil = Date().addingTimeInterval(0.26)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                guard let self else { return }
                if self.path == .falling { self.panel.orderFrontRegardless() }
                self.door.close(lock: false)
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
        case .home: if lock { door.close(lock: true) }
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
            if Date() < holdUntil { return }
            vy += 2400 * dt
            pos.y -= vy * dt
            if pos.y <= floorY {
                pos.y = floorY
                go(.floor)
                set(.greet, then: afterLanding)
            }
        case .floor:
            if mood == "asleep" { goHome(lock: false) }
            if state == .walk {
                pos.x += dir * 24 * speed * dt
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
            if pos.x <= doorX { pos.x = doorX; door.open(); go(.entering) }
        case .entering:
            shrink -= 2.5 * dt
            if shrink <= 0 {
                shrink = 1
                panel.orderOut(nil)
                go(.home)
                // One frame after the pet is fully inside.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 / tickHz) { [weak self] in
                    guard let self, self.path == .home else { return }
                    self.door.close(lock: self.lockWhenHome)
                }
                return
            }
        }
        animClock += (skin.fpsByMood[mood] ?? skin.fps * speed) * dt
        while animClock >= 1 {
            animClock -= 1
            advanceFrame()
        }
        panel.setFrameOrigin(NSPoint(x: pos.x, y: pos.y))
        draw()
        placeSign()
        placeBubble()
    }

    func setMood(_ m: String, reason: String?) {
        if m != mood { print("mood \(mood) -> \(m)") }
        mood = m
        sleepNote = m == "asleep" ? "zzz  " + (reason ?? brokeReason) : nil
        placeBubble()
    }

    func setBubble(_ text: String) {
        bubbleLabel.stringValue = text
        bubbleLabel.sizeToFit()
        bubblePanel.setContentSize(bubbleLabel.frame.size)
    }

    func say(_ text: String, for seconds: TimeInterval) {
        setBubble(text)
        bubbleUntil = Date().addingTimeInterval(seconds)
        placeBubble()
    }

    // Money landed in the wallet: play eat (on screen only) and show the amount.
    func eat(_ amount: String) {
        say(amount, for: 4)
        if path == .floor && state != .eat { set(.eat, then: next) }
    }

    func placeBubble() {
        if Date() >= bubbleUntil {
            guard let note = sleepNote else { if bubblePanel.isVisible { bubblePanel.orderOut(nil) }; return }
            if bubbleLabel.stringValue != note { setBubble(note) }
        }
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
        if !show { signShownAt = nil; if signPanel.isVisible { signPanel.orderOut(nil) }; return }
        if signShownAt == nil { signShownAt = Date() }
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
        if mood == "hungry" { t = t.scaledBy(x: 0.88, y: 1) }
        if mood == "thriving" && path == .floor && state == .walk {
            t = t.translatedBy(x: 0, y: abs(sin((Double(frame) + animClock) * .pi / 2)) * 3)
        }
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
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
                    .map { max(0, $0) } ?? 0 // a negative length would trap in prefix()
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
    let name: String; let mood: String; let moodReason: String?; let walletBalance: String?; let computeBalance: String?
    let impressionsToday: Int; let lastThoughts: [Thought]; let lastMeal: Meal?; let seeded: Bool
}
struct ThinkResult: Decodable { let action: String; let say: String?; let reason: String?; let requestId: String? }

let popoverWidth: CGFloat = 420
let brokeReason = "wallet too low to pay for 0G calls"

// Wei string to "0.0192 0G": 4 decimals, rounded down so the popover never shows more than the wallet holds.
func og4(_ wei: String?) -> String {
    guard let wei, !wei.isEmpty, wei.allSatisfy({ $0.isASCII && $0.isNumber }), var units = Decimal(string: wei) else { return "unknown" }
    units /= Decimal(sign: .plus, exponent: 14, significand: 1)
    var whole = Decimal()
    NSDecimalRound(&whole, &units, 0, .down)
    let digits = String(repeating: "0", count: max(0, 5 - "\(whole)".count)) + "\(whole)"
    return "\(digits.dropLast(4)).\(digits.suffix(4)) 0G"
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
    let stack = NSStackView()
    var campaign: Campaign?
    var info: PetInfo?
    var lastThink = "no think yet"
    var serverError: String?
    var thinking = false
    var lastImpression: [String: Date] = [:] // campaign id -> last report; server enforces the same window
    // Polls overlap (timer + after each think); a late reply must not roll the balance back and re-show a meal.
    var petSent = 0, petApplied = 0
    // Rebuild the popover only when what it shows changes, so a "copied" click survives the 10s polls.
    var shown = ""

    init(pet: Pet) {
        self.pet = pet
        super.init()
        item.button?.title = "Notchi"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.widthAnchor.constraint(equalToConstant: popoverWidth).isActive = true
        let vc = NSViewController()
        vc.view = stack
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false
        refresh()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reportImpression() }
    }

    // BUILD_GUIDE section 8: working state, sign visible 5s, once per campaign per minute.
    func reportImpression() {
        guard let c = campaign, c.line != nil, let since = pet.signShownAt, Date().timeIntervalSince(since) >= 5 else { return }
        if let last = lastImpression[c.campaignId], Date().timeIntervalSince(last) < 60 { return }
        lastImpression[c.campaignId] = Date()
        request("/impressions", body: ["impressions": [["petKey": petName, "campaignId": c.campaignId]]]) { _, err in
            if let err { print("impression not sent: \(err)") }
            self.refresh()
        }
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
                self.pet.setMood("asleep", reason: "can't reach the Notchi server")
            }
            if let data, let new = try? JSONDecoder().decode(PetInfo.self, from: data) {
                if self.info?.seeded == new.seeded, let gain = ogGain(self.info?.walletBalance, new.walletBalance) {
                    self.pet.eat(gain + (new.seeded ? " [seeded]" : ""))
                }
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
        if let i = info { pet.setMood(i.mood, reason: i.moodReason) }
        let key = "\(String(describing: info))|\(String(describing: campaign))|\(serverError ?? "")|\(lastThink)"
        if key == shown { return }
        shown = key
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if seeded { stack.addArrangedSubview(label("SEEDED DATA: not real 0G tokens", 13, .bold, .systemRed)) }
        if let e = serverError { stack.addArrangedSubview(label("Server: \(e)", 12, .regular, .systemRed)) }
        if let i = info {
            stack.addArrangedSubview(label(i.name, 13, .regular, .secondaryLabelColor))
            let colors = ["thriving": NSColor.systemGreen, "stable": .systemBlue, "hungry": .systemOrange]
            stack.addArrangedSubview(label(i.mood.uppercased(), 32, .heavy, colors[i.mood] ?? .systemGray))
            if i.mood == "asleep" { stack.addArrangedSubview(label(i.moodReason ?? brokeReason, 13, .regular, .secondaryLabelColor)) }
            stack.addArrangedSubview(row("Wallet", og4(i.walletBalance) + tag))
            stack.addArrangedSubview(row("Impressions today", "\(i.impressionsToday)" + tag))
        } else {
            stack.addArrangedSubview(label("No pet data yet", 15, .medium, .secondaryLabelColor))
        }
        stack.addArrangedSubview(label("Sign", 13, .regular, .secondaryLabelColor))
        stack.addArrangedSubview(label(campaign.map { "\"\($0.line ?? "(line unknown)")\" by \($0.brand)\(tag)" } ?? "No active campaign", 15, .medium))
        stack.addArrangedSubview(label("Last thoughts (click to copy request ID)", 13, .regular, .secondaryLabelColor))
        let thoughts = info?.lastThoughts.prefix(3) ?? []
        if thoughts.isEmpty { stack.addArrangedSubview(label("none yet", 13, .regular, .secondaryLabelColor)) }
        for t in thoughts {
            let b = NSButton(title: "", target: self, action: #selector(copyId(_:)))
            b.isBordered = false
            b.identifier = NSUserInterfaceItemIdentifier(t.requestId)
            b.attributedTitle = NSAttributedString(string: t.action + String(repeating: " ", count: max(1, 10 - t.action.count)) + t.requestId, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.linkColor])
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(label("Last think: \(lastThink)", 11, .regular, .tertiaryLabelColor))
        popover.contentSize = stack.fittingSize
    }

    @objc func copyId(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        sender.attributedTitle = NSAttributedString(string: "copied \(id)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.systemGreen])
    }

    func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.preferredMaxLayoutWidth = popoverWidth - 32
        return l
    }

    func row(_ key: String, _ value: String) -> NSStackView {
        let k = label(key, 15, .regular, .secondaryLabelColor)
        let v = label(value, 17, .semibold)
        v.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        let row = NSStackView(views: [k, v])
        row.alignment = .firstBaseline
        return row
    }
}

assert(ogGain("1000000000000000000", "1005000000000000000") == "+0.005 0G")
assert(ogGain("123456789012345678901", "123456789012345678902") == "+0.000000000000000001 0G")
assert(og4("19279999998320000") == "0.0192 0G" && og4("0") == "0.0000 0G" && og4("1000000000000000000000") == "1000.0000 0G")
assert(og4("99999999999999") == "0.0000 0G" && og4(nil) == "unknown")
assert(og4("-5") == "unknown" && og4("0x1f") == "unknown" && og4(" 5") == "unknown" && og4("") == "unknown")
assert(ogGain("5", "5") == nil && ogGain("5", "4") == nil && ogGain(nil, "5") == nil)
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let skin = loadSkin() else { exit(1) }
let door = Door(art: skin.doors, scale: skin.scale)
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
