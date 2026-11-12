import NotchiCore
import AppKit
import CryptoKit
import Network
import UserNotifications

// ---- Device key (PLAN_V2 A3) ----
// A P-256 key inside this Mac's Secure Enclave. The blob in UserDefaults is opaque and only usable by this chip;
// the private key never leaves it. Views, think calls and clicks are signed with it once the pet is paired.
let deviceSigner: SecureEnclave.P256.Signing.PrivateKey? = {
    guard SecureEnclave.isAvailable else { return nil }
    let store = "deviceKey"
    if let blob = UserDefaults.standard.data(forKey: store), let k = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) { return k }
    guard let k = try? SecureEnclave.P256.Signing.PrivateKey() else { return nil }
    UserDefaults.standard.set(k.dataRepresentation, forKey: store)
    return k
}()

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
let devicePublicKey: String? = deviceSigner.map { b64url($0.publicKey.x963Representation) }

/** Signature over the server's canonical string: METHOD, path, unix ms, SHA-256 hex of the body. */
func deviceSign(method: String, path: String, body: Data) -> (key: String, time: String, sig: String)? {
    guard let k = deviceSigner, let pub = devicePublicKey else { return nil }
    let time = String(Int64(Date().timeIntervalSince1970 * 1000))
    let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    let message = "\(method)\n\(path)\n\(time)\n\(hash)"
    guard let sig = try? k.signature(for: Data(message.utf8)) else { return nil }
    return (pub, time, b64url(sig.derRepresentation))
}

let tickHz = 30.0
// Seconds of quiet after the agent stops before the pet climbs home. Override with NOTCHI_HOME_AFTER.
// Popover settings, persisted in UserDefaults. NOTCHI_HOME_AFTER still overrides at launch.
let defaults = UserDefaults.standard
var homeAfter = TimeInterval(ProcessInfo.processInfo.environment["NOTCHI_HOME_AFTER"] ?? "") ?? (defaults.object(forKey: "homeAfter") as? Double ?? 75)
var walkSpeed = defaults.object(forKey: "walkSpeed") as? Double ?? 1
// Sponsored hooks are opt-in: off until the developer turns them on (asked once on first launch).
var sponsoredOn = defaults.object(forKey: "sponsored") as? Bool ?? false
var quietHours = defaults.object(forKey: "quietHours") as? Bool ?? false // opt-in: developers code at night; when on, no hooks 22:00-08:00
let dailyViewCap = 120 // the server enforces the same cap
func inQuietHours(_ d: Date = Date()) -> Bool {
    let h = Calendar.current.component(.hour, from: d)
    return quietHours && (h >= 22 || h < 8)
}
// Off: on every normal desktop, never over full-screen apps. On: over full-screen apps too.
// (Pinning to the launch Space hid the pet on the desktop whenever Notchi was started from a full-screen app.)
var allDesktops = defaults.bool(forKey: "allDesktops")
// Come-back reminders every N minutes after Stop or an approval request; 0 is off.
var reminderMinutes = defaults.object(forKey: "reminderMinutes") as? Double ?? 5
func spacesBehavior() -> NSWindow.CollectionBehavior {
    allDesktops ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary] : [.canJoinAllSpaces, .stationary]
}

enum PetState: String, CaseIterable {
    case greet, walk, idle, sign, flag, celebrate, fail, climb, eat, hover, annoy, backflip, moonwalk
    case sit, yawn, gaze, grabbed, thrown, land, edgepeek, night, tools, special, hatch, evolve
    case chase, gulp, covereyes, tangled, juggle, wrist, focus
    /// The pack row this state draws. Holding the line is the hold row, with the plate overhead.
    var row: Row { self == .sign ? .hold : Row(rawValue: rawValue)! }
}

let loopingStates: Set<PetState> = [.walk, .climb, .idle, .sign, .flag, .hover, .annoy, .moonwalk, .sit, .gaze, .grabbed, .thrown, .night, .tools, .hatch, .tangled, .focus]

// Where the pet is, separate from what it is doing.
enum Path: String { case home, falling, floor, toWall, climbing, ceiling, entering, held, airborne }

// A species pack (NotchiCore) prepared for drawing. See assets/pets/<id>/pet.json and docs/design/1.0.
struct Strip {
    let row: Row              // the row actually drawn (after fallbacks)
    let frames: [CGImage]     // that row's frames
    let subset: [Int]?        // fallback frames within the row, or nil for the spec's sequence
    let rotated: Bool         // walk standing in for climb, rotated onto the wall
}

struct Skin {
    let name: String          // species id, the pack folder
    let loaded: LoadedPack
    let species: Species?
    let accent: CGColor
    let size: CGSize
    let footPadding: CGFloat
    let strips: [PetState: Strip]
    let doors: [DoorState: CGImage]  // packs carry no door art yet; the default door is drawn
    let scale: CGFloat               // points per sheet pixel
    var pack: Pack { loaded.pack }
    var geometry: PetGeometry { PetGeometry(cellW: pack.cell.w, cellH: pack.cell.h, scale: scale) }
}

// The packaged .app carries assets in Contents/Resources/assets; swift run reads the repo's top-level assets/.
let assetsDir: URL = {
    if let r = Bundle.main.resourceURL?.appendingPathComponent("assets/pets"), FileManager.default.fileExists(atPath: r.path) { return r.deletingLastPathComponent() }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets")
}()

func hexColor(_ hex: String) -> CGColor {
    guard let c = RGB(hex: hex) else { return CGColor(red: 1, green: 0x5A / 255.0, blue: 0x3C / 255.0, alpha: 1) }
    return CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
}

// Loads `want` (or NOTCHI_SKIN, or the saved species, or Notchi); falls back to the first species that loads.
func loadSkin(_ want: String? = nil) -> Skin? {
    let pick = want ?? ProcessInfo.processInfo.environment["NOTCHI_SKIN"] ?? defaults.string(forKey: "skin") ?? Roster.defaultId
    let order = [pick] + Roster.all.map(\.id).filter { $0 != pick }
    for id in order { if let s = loadSkin(id: id) { return s } }
    print("no loadable pet in \(assetsDir.path)/pets")
    return nil
}

func loadSkin(id: String) -> Skin? {
    let loaded: LoadedPack
    do { loaded = try LoadedPack.load(dir: assetsDir.appendingPathComponent("pets/\(id)")) } catch {
        print("pet \(id): \(error.localizedDescription)")
        return nil
    }
    var strips: [PetState: Strip] = [:]
    for s in PetState.allCases {
        guard let r = Fallback.resolve(s.row, in: loaded.pack), let frames = loaded.frames[r.row] else { continue }
        strips[s] = Strip(row: r.row, frames: frames, subset: r.frames, rotated: r.rotated)
    }
    guard strips[.walk] != nil else { print("pet \(id) has no walk frames"); return nil }
    let scale: CGFloat = 2.0 / 7  // one sprite unit (7 sheet px) draws at 2 points
    let (cw, ch) = loaded.pack.cell
    print("pet \(id): pack v\(loaded.pack.version), \(loaded.frames.count) rows\(loaded.pack.canHoldLine ? "" : ", can't hold the line")")
    return Skin(name: id, loaded: loaded, species: Roster.species(id), accent: hexColor(loaded.pack.notchi.accent),
                size: CGSize(width: CGFloat(cw) * scale, height: CGFloat(ch) * scale),
                footPadding: CGFloat(ch - 194) * scale, strips: strips, doors: [:], scale: scale)
}

// Design tokens: Ink, Paper. The accent comes from the active pet.
let inkColor = CGColor(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0B / 255.0, alpha: 1)
let paperColor = CGColor(red: 0xF4 / 255.0, green: 0xF2 / 255.0, blue: 0xED / 255.0, alpha: 1)

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
    panel.collectionBehavior = spacesBehavior()
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
    var state = DoorState.closed
    /// The active pet lends the door its glow.
    func setAccent(_ c: CGColor) { glow.fillColor = c; glow.shadowColor = c }
    var gen = 0  // bumps on every open/close so a stale animation step can't reopen the door

    init(art: [DoorState: CGImage], scale: CGFloat, accent: CGColor) {
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
        glow.fillColor = accent
        glow.shadowColor = accent
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
        lockBody.fillColor = paperColor
        let shackle = CGMutablePath()
        shackle.addArc(center: CGPoint(x: mid, y: 9), radius: 2, startAngle: 0, endAngle: .pi, clockwise: false)
        lockShackle.path = shackle
        lockShackle.fillColor = nil
        lockShackle.strokeColor = paperColor
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
        if state != .open { Feel.event("door.open") }
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
        if state == .open { Feel.event("door.close") }
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
    var skin: Skin
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
    // The sponsored line, from GET /campaigns/active, on the plate the pet holds overhead (hold row).
    // The plate never mirrors, never scrolls and never truncates (spec R2 §2).
    lazy var signPanel = overlayPanel(CGSize(width: 60, height: 36), level: .statusBar)
    var signText = ""
    var signBrand = ""
    var plate: (image: CGImage, layout: PlateLayout, backing: CGFloat)?
    let signClick = ClickView(frame: .zero)
    var signShownAt: Date?
    var onSignClick: (() -> Void)?
    var signLinks = false // the current campaign has a link to open
    // Short speech bubble ("+0.0002 NEAR food"). Above the pet, or under the door while it is home.
    let bubblePanel = overlayPanel(CGSize(width: 10, height: 20), level: .statusBar)
    let bubbleLabel = NSTextField(wrappingLabelWithString: "")
    var bubbleUntil = Date.distantPast
    // From GET /pets/:name. Asleep keeps the pet home with sleepNote under the door.
    var mood = "stable"
    var sleepNote: String?
    // Between PreToolUse/PostToolUse and Stop: 12 fps, a bit quicker, with a small "..." bubble.
    var working = false
    // Claude Code is waiting on a permission prompt; the popover offers to bring the terminal forward.
    var waiting = false
    var speed: Double { Rates.multiplier(mood: mood) }
    // Accessories: one layer per slot, inside the sprite layer so they share its flips and squashes.
    var accLayers: [Slot: CALayer] = [:]
    // From the Closet (Growth+Mac.swift); a free try-on overrides it for a few seconds.
    var wornItems: [String] = []
    var wornOverride: [String]?
    var worn: [String] { wornOverride ?? wornItems }
    // Before hatching the pet is an egg: it shows the hatch row, never walks, holds no line (R3 §3).
    var egg = false
    var eggFrame = 0
    var onEggSkip: (() -> Void)?
    var onStomp: (() -> Void)?
    // A companion: every animation, no sign, no thinking, no views (spec D §2).
    var isCompanion = false
    var ducked = false  // hidden for a screen share or full screen (Privacy+Mac.swift)
    var timers: [Timer] = []
    // Tricks: the backflip's jump arc lifts the whole window; the moonwalk slides against the facing.
    var trickStart = Date.distantPast
    var liftY: CGFloat = 0
    // Pets alive (Alive+Pet.swift)
    var scheduler = IdleScheduler(now: Date(), seed: SeededRNG.daySeed(Date()))
    var schedulerDay = SeededRNG.daySeed(Date())
    var lastAgentEvent = Date()
    var napping = false
    var night = Context.isNight(Date())
    var gaze = Gaze()
    var gazeFrame = 2
    var beforeGaze: PetState?
    var lastMouse = NSPoint.zero
    var lastMouseMove = Date.distantPast
    var grabOffset = CGPoint.zero
    var dragSamples: [(Date, NSPoint)] = []
    var body: Physics.Body?
    var dizzy = false
    var throws_: [Date] = []
    var power = Context.Power.normal
    var offline = false
    let network = NWPathMonitor()
    var currentProp: Prop?
    var pendingSignature = false
    var squashFrame: Int?
    var onContextChange: (() -> Void)?

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
        let grab = GrabView(frame: CGRect(origin: .zero, size: skin.size))
        grab.autoresizingMask = [.width, .height]
        grab.onClick = { [weak self] in
            guard let self else { return }
            if self.egg && NSEvent.modifierFlags.contains(.option) { self.onEggSkip?(); return }  // option-click hatches now
            self.poke()
        }
        grab.onGrab = { [weak self] in self?.beginGrab(at: $0) }
        grab.onDrag = { [weak self] in self?.drag(to: $0) }
        grab.onRelease = { [weak self] in self?.release(at: $0) }
        grab.onSquish = { [weak self] in self?.squish(stage: $0, pressure: $1) }
        panel.contentView?.addSubview(grab)
        // The plate opens the brand's link; it only takes clicks while the cursor is on it (see updateCursor).
        signClick.autoresizingMask = [.width, .height]
        signClick.onClick = { [weak self] in self?.onSignClick?() }
        signPanel.contentView?.addSubview(signClick)
        signPanel.contentView?.layer?.magnificationFilter = .nearest
        for slot in Slot.allCases {
            let l = CALayer()
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.zPosition = CGFloat(slot.rawValue + 1)  // neck, then face, then head
            sprite.addSublayer(l)
            accLayers[slot] = l
        }
        bubbleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        bubbleLabel.textColor = .black
        bubbleLabel.drawsBackground = true
        bubbleLabel.backgroundColor = .white
        bubblePanel.contentView?.addSubview(bubbleLabel)
        timers.append(Timer.scheduledTimer(withTimeInterval: 1 / tickHz, repeats: true) { [weak self] _ in self?.tick() })
        startContextMonitors()
    }

    func go(_ p: Path) {
        if p != path { print("path \(path.rawValue) -> \(p.rawValue)") }
        path = p
    }

    func set(_ s: PetState, then after: PetState? = nil) {
        let s = egg ? .hatch : s
        let after = egg ? .hatch : after
        if s != state { print("state \(state.rawValue) -> \(s.rawValue)") }
        state = s
        next = after ?? s
        frame = 0
        animClock = 0
    }

    // Leave the house (or drop off the wall) and land on the floor, then show `s`.
    func comeOut(then s: PetState) {
        if staysHome(mood: mood, agentWorking: working) { return }
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
                if self.path == .falling && self.onHomeSpace {
                    self.panel.setFrameOrigin(self.pos)
                    self.panel.orderFrontRegardless()
                }
                self.door.close(lock: false)
            }
        case .entering:
            door.close(lock: false)
        case .toWall, .climbing, .ceiling:
            break
        case .held, .airborne:
            return  // in the user's hand or in the air: it lands first
        }
        lockWhenHome = false
        shrink = 1
        vy = 0
        set(.greet)
        go(.falling)
    }

    func goHome(lock: Bool) {
        if egg && path != .home {  // an egg can't climb: it pops back behind the door
            go(.home); panel.orderOut(nil); door.close(lock: lock); return
        }
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
                if lockWhenHome { goHome(lock: true) }  // SessionEnd arrived mid-fall
            }
        case .floor:
            if staysHome(mood: mood, agentWorking: working) { goHome(lock: false) }
            // The sign is the ad state and gets the most screen time, so it strolls at 0.4 instead of standing still.
            if state == .moonwalk {
                pos.x += Arcs.moonwalkVelocity(facing: dir, walkPointsPerSecond: 24 * walkSpeed) * dt
                if pos.x < leftX || pos.x > rightX { pos.x = min(max(pos.x, leftX), rightX); set(.walk) }
            }
            if state == .walk || state == .sign {
                pos.x += dir * 24 * speed * walkSpeed * (state == .sign ? (working ? 0.6 : 0.4) : 1) * dt
                if pos.x < leftX { pos.x = leftX; dir = 1 }
                if pos.x > rightX { pos.x = rightX; dir = -1 }
            }
            if state == .walk || state == .idle, Date().timeIntervalSince(lastActive) > homeAfter {
                goHome(lock: false)
            }
            aliveTick(now: Date())
            if pendingSignature && [.walk, .idle, .sign, .tools].contains(state) && !waiting {
                pendingSignature = false
                set(.special, then: state)
            }
        case .held:
            break  // follows the cursor (drag)
        case .airborne:
            airborneTick(dt: dt)
        case .toWall:
            pos.x += 140 * dt
            if pos.x >= rightX { pos.x = rightX; set(.climb); go(.climbing) }
        case .climbing:
            pos.y += 140 * dt
            // Upside down on the top edge: the flipped sprite's feet are footPadding below its top, so lift it by that.
            if pos.y >= topY { pos.y = topY + skin.footPadding; dir = -1; set(.walk); go(.ceiling) }
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
        animClock += (Rates.fps(strip.row, mood: mood) ?? 8) * Context.frameRateFactor(power) * dt
        while animClock >= 1 {
            animClock -= 1
            advanceFrame()
        }
        // backflip: frames 1-4 are airborne; the app adds the 0.5 s arc (pet.json arcs)
        liftY = state == .backflip && path == .floor
            ? Arcs.backflipLift(t: Date().timeIntervalSince(trickStart) - 1 / (Rates.fps(.backflip, mood: "stable") ?? 12),
                                bodyHeight: Arcs.bodyHeight(skin.pack) * skin.scale)
            : 0
        panel.setFrameOrigin(NSPoint(x: pos.x, y: pos.y + liftY))
        // Came out while you were on another Space: show it once you're back on the home one.
        if !panel.isVisible && onHomeSpace && Date() >= holdUntil { panel.orderFrontRegardless() }
        draw()
        placeSign()
        placeBubble()
        updateCursor()
    }

    // The door's window is ordered in once at launch and never out, so it marks Notchi's home Space.
    var onHomeSpace: Bool { allDesktops || door.panel.isOnActiveSpace }

    func applySpaces() {
        for w in [panel, signPanel, bubblePanel, door.panel] { w.collectionBehavior = spacesBehavior() }
    }

    // A reminder fired: wave if you can actually see the pet. Already waving the approval flag counts.
    func wave() {
        guard path == .floor, panel.isVisible, onHomeSpace, state != .flag, state != .greet else { return }
        set(.greet, then: loopingStates.contains(state) ? state : next)
    }

    // Cursor play. Cosmetic only: nothing here touches the backend, balances or hooks.
    var annoyance = 0
    var lastPoke = Date.distantPast
    var beforeFun: PetState?
    // Working, approval and a live bubble outrank hover and annoyance.
    var busy: Bool { working || waiting || Date() < bubbleUntil }

    // The overlay stays click-through except while the cursor is over a visible pixel of the pet.
    func updateCursor() {
        let mouse = NSEvent.mouseLocation
        let inside = !ducked && (path == .floor || path == .held) && onHomeSpace && panel.isVisible && opaque(at: mouse)
        updateGaze(mouse: mouse, inside: inside)
        let overSign = !ducked && signPanel.isVisible && signPanel.frame.contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        // the sign is clickable only under the cursor, and never while the agent waits for approval
        let signTakesClick = overSign && !waiting && signLinks
        if signPanel.ignoresMouseEvents == signTakesClick { signPanel.ignoresMouseEvents = !signTakesClick }
        if signTakesClick { NSCursor.pointingHand.set() }
        if annoyance > 0 && Date().timeIntervalSince(lastPoke) > 6 { annoyance = 0 }
        if state == .annoy && (annoyance == 0 || busy) {
            set(beforeFun ?? .walk)
            beforeFun = nil
        } else if state == .hover && (!inside || busy) {
            set(beforeFun ?? .walk)
            beforeFun = nil
        } else if inside && !busy && (state == .walk || state == .idle) {
            beforeFun = state
            set(.hover)
            Feel.haptic(.purr, lineUp: plate != nil && signPanel.isVisible)
        }
        if state == .hover { dir = mouse.x < pos.x + size.width / 2 ? -1 : 1 }
    }

    func poke() {
        guard path == .floor, !busy, [.walk, .idle, .hover, .annoy].contains(state) else { return }
        annoyance += 1
        lastPoke = Date()
        Feel.sound(Sounds.poke(click: annoyance))
        Feel.haptic(annoyance >= 5 ? .stomp : .boop)
        if annoyance == 5 { onStomp?() }
        if state != .annoy {
            if state != .hover { beforeFun = state }
            set(.annoy)
        }
    }

    // Alpha of the current frame under a screen point, not the window rect.
    func opaque(at p: NSPoint) -> Bool {
        let f = panel.frame
        guard f.contains(p) else { return false }
        let img = strip.frames[sheetFrame]
        var x = (p.x - f.minX) / f.width
        if flipped { x = 1 - x }
        let px = min(Int(x * CGFloat(img.width)), img.width - 1)
        let py = min(Int((1 - (p.y - f.minY) / f.height) * CGFloat(img.height)), img.height - 1)
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: -px, y: -(img.height - 1 - py), width: img.width, height: img.height))
        return (ctx.data?.load(as: UInt8.self) ?? 0) > 0
    }

    var flipped: Bool { [.walk, .sign, .hover, .annoy, .moonwalk].contains(state) && dir < 0 }

    // Frame order, with annoyance picking its part of the annoy row: 1-2 frown, 3-4 arms out, 5+ puffed and stomping.
    // Frame indices within the strip's row: a fallback subset, or the spec's sequence (idle by mood, annoy by clicks).
    var seq: [Int] { strip.subset ?? pickedFrames() ?? Sequence.frames(strip.row, count: strip.frames.count, mood: mood, clicks: annoyance) }
    /// The sheet frame on screen now, for anchors.
    var sheetFrame: Int { seq[min(frame, seq.count - 1)] }

    func setMood(_ m: String, reason: String?) {
        if m != mood { print("mood \(mood) -> \(m)") }
        mood = m
        // asleep (can't read the chain) and hungry (can't pay for an AI call) both show why, next to the pet
        sleepNote = m == "asleep" || (m == "hungry" && reason != nil) ? "zzz  " + (reason ?? brokeReason) : nil
        placeBubble()
    }

    func setBubble(_ text: String) {
        bubbleLabel.stringValue = text
        bubbleLabel.preferredMaxLayoutWidth = 220
        bubbleLabel.frame.size = bubbleLabel.fittingSize
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
        Feel.event("meal")
        if path == .floor && state != .eat { set(.eat, then: next) }
    }

    func placeBubble() {
        if Date() >= bubbleUntil {
            guard let note = sleepNote ?? (working && path == .floor ? "\u{2026}" : nil) else { if bubblePanel.isVisible { bubblePanel.orderOut(nil) }; return }
            if bubbleLabel.stringValue != note { setBubble(note) }
        }
        let w = bubblePanel.frame.width, h = bubblePanel.frame.height
        var x = pos.x + size.width / 2 - w / 2
        var y = pos.y + size.height - 6 + (signPanel.isVisible ? signPanel.frame.height + 2 : 0)
        if path == .home { x = door.center.x - w / 2; y = door.panel.frame.minY - h - 2 }
        if path == .ceiling { y = pos.y - h + skin.footPadding }
        x = min(max(x, leftX), mainScreen.visibleFrame.maxX - w)
        bubblePanel.setFrameOrigin(NSPoint(x: x, y: min(y, mainScreen.visibleFrame.maxY - h)))
        if !bubblePanel.isVisible && onHomeSpace { bubblePanel.orderFrontRegardless() }
    }

    /// Puts `text` on the plate (nil takes it down). `brand` is for the disclosure: VoiceOver and the hover card.
    func setSign(_ text: String?, brand: String = "") {
        let text = text ?? ""
        guard text != signText || brand != signBrand else { return }  // render() calls this every poll
        signText = text
        signBrand = brand
        renderPlate()
        let label = text.isEmpty ? "" : "Sponsored, \(brand.isEmpty ? "a brand" : brand): \(text)"
        signPanel.contentView?.setAccessibilityLabel(label)
        signPanel.contentView?.setAccessibilityRole(.button)
        signClick.toolTip = text.isEmpty ? nil : "Sponsored by \(brand.isEmpty ? "a brand" : brand).\nWhy this line: brands pay for real views while your agent works, and that pays for your pet's thinking."
    }

    func renderPlate() {
        guard !signText.isEmpty, let kit = skin.pack.notchi.signKit, let kitImage = skin.loaded.kit else { plate = nil; return }
        let backing = mainScreen.backingScaleFactor
        guard let (image, layout) = PlateRenderer.render(line: signText, kitImage: kitImage, kit: kit, scale: skin.scale, backing: backing) else { plate = nil; return }
        plate = (image, layout, backing)
        let size = CGSize(width: CGFloat(image.width) / backing, height: CGFloat(image.height) / backing)
        signPanel.setContentSize(size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        signPanel.contentView?.layer?.contents = image
        signPanel.contentView?.layer?.contentsScale = backing
        CATransaction.commit()
    }

    func placeSign() {
        let show = path == .floor && state == .sign && plate != nil
        guard show, let plate, let r = Plate.frame(plate.layout, pack: skin.pack, frame: sheetFrame, geometry: skin.geometry, flipped: flipped) else {
            signShownAt = nil; if signPanel.isVisible { signPanel.orderOut(nil) }; return
        }
        // bottom-centre on the plate anchor; the plate doesn't bob, the pet bobs under it
        let w = signPanel.frame.width
        let x = min(max(pos.x + r.midX - w / 2, leftX), mainScreen.visibleFrame.maxX - w)
        signPanel.setFrameOrigin(NSPoint(x: x, y: pos.y + r.minY))
        if !signPanel.isVisible && onHomeSpace { signPanel.orderFrontRegardless() }
        // An impression needs the sign really on screen: not on another Space, not behind a full-screen app.
        if signPanel.occlusionState.contains(.visible) {
            if signShownAt == nil { signShownAt = Date(); print("view: sign on screen (\(signText.prefix(40)))") }
        } else {
            signShownAt = nil
        }
    }

    func advanceFrame() {
        if path == .falling { return }  // hold the first greet frame mid-air
        frame += 1
        if frame >= seq.count {
            if loopingStates.contains(state) { frame = 0 } else { set(next) }
        }
    }

    var strip: Strip { skin.strips[state] ?? skin.strips[.walk]! }

    func draw() {
        var t = CGAffineTransform.identity
        if flipped { t = t.scaledBy(x: -1, y: 1) }
        if state == .annoy && annoyance >= 5 && frame % 2 == 1 { t = t.translatedBy(x: 0, y: -2) }  // the stomp
        // Body only: the sign and bubbles are separate windows, so they stay upright.
        if path == .ceiling { t = t.scaledBy(x: 1, y: -1) }
        // v6 climb frames are pre-rotated for the right wall; walk standing in for climb is turned onto it.
        if strip.rotated { t = t.rotated(by: .pi / 2) }
        let phase = Double(frame) + animClock
        if mood == "thriving" && path == .floor && state == .walk {
            t = t.translatedBy(x: 0, y: abs(sin(phase * .pi / 2)) * 3)
        }
        // Emotions from hooks: happy = squash + bounce, sad = slump, approval = jump.
        if path == .floor {
            switch state {
            case .celebrate:
                let up = abs(sin(phase * .pi / 2))
                let squash = (1 - up) * 0.1
                t = t.translatedBy(x: 0, y: up * 6 - size.height * squash / 2).scaledBy(x: 1 + squash, y: 1 - squash)
            case .fail:
                t = t.translatedBy(x: 0, y: -size.height * 0.05).scaledBy(x: 1.04, y: 0.9)
            case .flag:
                t = t.translatedBy(x: 0, y: abs(sin(phase * .pi / 3)) * 8)
            default: break
            }
        }
        if path == .entering {
            // Shrink towards the top centre, into the door.
            t = CGAffineTransform(translationX: 0, y: size.height / 2 * (1 - shrink)).scaledBy(x: shrink, y: shrink)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = strip.frames[sheetFrame]
        sprite.setAffineTransform(t)
        // accessories in the sprite's own (unflipped) coordinates; the sprite's transform mirrors them with it
        let wear = Dictionary(uniqueKeysWithValues: Accessories.drawOrder(worn).map { (Slot.of($0), $0) })
        for (slot, layer) in accLayers {
            guard let item = wear[slot], let sheet = skin.pack.notchi.accessories, let img = skin.loaded.accessory(item),
                  let r = Accessories.frame(sheet: sheet, pack: skin.pack, row: strip.row, frame: sheetFrame, geometry: skin.geometry, flipped: false) else {
                layer.contents = nil; continue
            }
            layer.contents = img
            layer.frame = r
        }
        CATransaction.commit()
    }

    /// A trick (spec R4 §8). Learning them comes later; for now the demo menu plays them.
    func trick(_ s: PetState) {
        guard path == .floor, [.backflip, .moonwalk].contains(s), skin.strips[s] != nil else { return }
        trickStart = Date()
        set(s, then: state == .sign ? .sign : .walk)
        if s == .moonwalk { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.state == .moonwalk { self?.set(.walk) } } }
    }

    func askApproval() {
        waiting = true
        Feel.event("PermissionRequest")
        comeOut(then: .flag)
    }

    // Live avatar switch from the popover. Door art stays as loaded at launch.
    func setSkin(_ s: Skin) {
        let floorDelta = s.footPadding - skin.footPadding
        skin = s
        door.setAccent(s.accent)
        renderPlate()
        panel.setContentSize(s.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = CGRect(origin: .zero, size: s.size)
        CATransaction.commit()
        switch path {
        case .floor: pos.y -= floorDelta
        case .ceiling: pos.y = topY + s.footPadding
        case .climbing: pos.x = rightX
        default: break
        }
        frame = 0
        draw()
    }

    // Maps a Claude Code hook event to the pet. See CLAUDE.md, "Pet state machine".
    func handle(event: String, notification: String?, tool: String? = nil, command: String? = nil) {
        agentEvent(event, tool: tool, command: command)
        switch event {
        case "SessionStart":
            sessionLive = true
        case "UserPromptSubmit":
            sessionLive = true
            waiting = false
            working = true // the agent's work starts at the prompt; the sign goes up now, not at the first tool call
            if path == .floor { lastActive = Date(); set(.greet, then: .sign) } else { comeOut(then: .sign) }
        case "PreToolUse", "PostToolUse":
            lastActive = Date()
            waiting = false
            working = true
            let w = workingState()
            if path != .floor { comeOut(then: w) }
            else if state == .greet { next = w }
            else if state != w && state != .special { set(w) }
        case "PermissionRequest":
            askApproval()
        case "Notification":
            if notification == "permission_prompt" { askApproval() }
            else if notification == "idle_prompt", path == .floor { set(.idle) }
        case "Stop":
            working = false
            waiting = false
            lastActive = Date()
            Feel.event("Stop")
            if path == .floor { set(.celebrate, then: .walk) }
        case "StopFailure":
            working = false
            waiting = false
            lastActive = Date()
            Feel.event("StopFailure")
            if path == .floor { set(.fail, then: .idle) }
        case "SessionEnd":
            working = false
            waiting = false
            sessionLive = false
            goHome(lock: true)
        default: break
        }
    }
}

// Nudges you back when Claude Code is done or waiting on you. Cosmetic: never touches hooks' replies, balances or spending.
final class Reminders {
    let pet: Pet
    var message: String?
    var project: String?
    var timer: Timer?

    init(pet: Pet) { self.pet = pet }

    func handle(_ hook: [String: Any]) {
        switch hook["hook_event_name"] as? String {
        case "Stop": arm("Claude Code is done", hook)
        case "PermissionRequest": arm(approval, hook)
        case "Notification" where hook["notification_type"] as? String == "permission_prompt": arm(approval, hook)
        case "UserPromptSubmit", "SessionEnd": cancel()
        // The approval was answered and tools are running again.
        case "PreToolUse", "PostToolUse": if message == approval { cancel() }
        default: break
        }
    }

    let approval = "Claude Code needs your approval"

    func arm(_ text: String, _ hook: [String: Any]) {
        message = text
        project = (hook["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        reschedule()
    }

    func cancel() {
        message = nil
        timer?.invalidate()
        timer = nil
    }

    // Also called when the interval setting changes.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard message != nil, reminderMinutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: reminderMinutes * 60, repeats: true) { [weak self] _ in self?.fire() }
    }

    func fire() {
        guard let message else { return }
        notify(title: message, body: project.map { "In \($0)" } ?? "Back to your terminal")
        pet.wave()
    }

    // UNUserNotificationCenter throws without a bundle id (swift run has none); osascript works either way.
    func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return osascript(title, body) }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return DispatchQueue.main.async { self.osascript(title, body) } }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "notchi-reminder", content: content, trigger: nil))
        }
    }

    func osascript(_ title: String, _ body: String) {
        func quote(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ") + "\""
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \(quote(body)) with title \(quote(title))"]
        do { try p.run() } catch { print("reminder not shown: \(error)") }
    }
}

// Takes clicks on the pet only while the panel isn't click-through (see Pet.updateCursor).
final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Minimal HTTP listener for the hooks. Replies 200 with an empty body at once, never a decision.
final class HookServer {
    let listener: NWListener
    let onEvent: ([String: Any]) -> Void
    /// PermissionRequest: the connection stays open until `reply` is called with the user's answer (or nil).
    var onPermission: (([String: Any], @escaping (Data?) -> Void) -> Void)?
    /// Git hooks (R4 §4) post one line: {"type":"git","event":...,"repo":<hash>}.
    var onGit: ((GitEvent) -> Void)?

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
                    print("Port 47474 is taken: \(productName) is probably already running. Stop it with: pkill -x Notchi")
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
                    let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    self.finish(conn, path: path, body: Data(body.prefix(length)))
                    return
                }
            }
            if done || err != nil || buf.count > 8_000_000 { conn.cancel(); return }
            self.read(conn, buf)
        }
    }

    func respond(_ conn: NWConnection, _ body: Data?) {
        let b = body ?? Data()
        var reply = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(b.count)\r\nConnection: close\r\n\r\n".utf8)
        reply.append(b)
        conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() })
    }

    func finish(_ conn: NWConnection, path: String, body: Data) {
        if path == "/git" {
            respond(conn, nil)
            if let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let e = GitEvent.parse(j) { onGit?(e) }
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], json["hook_event_name"] is String else {
            respond(conn, nil); return
        }
        if path == "/claude/permission", let onPermission {
            // held open until the user answers on a surface; the answer is the hook's output
            var replied = false
            onPermission(json) { [weak self] data in
                guard !replied else { return }
                replied = true
                self?.respond(conn, data)
            }
        } else {
            respond(conn, nil)  // every other event: answer at once, no decision
        }
        onEvent(json)
    }
}

struct Campaign: Decodable {
    let campaignId: String; let line: String?; let hooks: [String]?; let url: String?; let order: [Int]?; let brand: String; let ratePerImpression: String
    var allHooks: [String] { hooks?.isEmpty == false ? hooks! : line.map { [$0] } ?? [] }
}
struct Thought: Decodable { let action: String; let requestId: String; let at: Int; let model: String?; let chargeTx: String? }
struct PetInfo: Decodable {
    let name: String; let mood: String; let moodReason: String?; let walletBalance: String?; let computeBalance: String?
    let impressionsToday: Int; let lastThoughts: [Thought]; let seeded: Bool
    let paidViews: Int?; let earnedWei: String?; let level: Int?; let streak: Int? // nil: older server or chain unreadable
    let explorer: String? // nearblocks for the server's network
    let meals: [String]? // settlement txs that fed the compute budget: one meal each, for growth
}

/// Species are earned, never bought (spec D §2): starters are open; the rest show what unlocks them.
func speciesLock(_ id: String) -> String? { backend.growth.lockReason(id) }

/// Time the agent worked while you waited today (prompt to stop), counted on this Mac from hook events, never uploaded.
struct WaitClock {
    var day = "", seconds = 0.0, since: Date?
    static let maxStretch = 3600.0 // a lost Stop (crash, kill) must not count the whole night
    static func dayOf(_ d: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: d); return "\(c.year!)-\(c.month!)-\(c.day!)" }
    mutating func handle(_ event: String, at now: Date = Date()) {
        if WaitClock.dayOf(now) != day { day = WaitClock.dayOf(now); seconds = 0 }
        switch event {
        case "UserPromptSubmit": close(now); since = now
        case "Stop", "StopFailure", "SessionEnd": close(now)
        default: break
        }
    }
    mutating func close(_ now: Date) {
        if let s = since { seconds += min(max(now.timeIntervalSince(s), 0), WaitClock.maxStretch) }
        since = nil
    }
    func minutes(at now: Date = Date()) -> Int {
        guard WaitClock.dayOf(now) == day else { return 0 }
        return Int((seconds + (since.map { min(now.timeIntervalSince($0), WaitClock.maxStretch) } ?? 0)) / 60)
    }
}
struct ThinkResult: Decodable { let action: String; let say: String?; let reason: String?; let requestId: String? }

let popoverWidth: CGFloat = 320

/// Whether the pet keeps out of sight. Ads never depend on mood: a hungry pet (compute budget empty) still walks the
/// sponsored sign while the agent works, because that's how it earns food. Mood only stops the paid AI calls.
/// Only an asleep pet (the chain can't be read) with no agent work stays home.
func staysHome(mood: String, agentWorking: Bool) -> Bool { mood == "asleep" && !agentWorking }
// The product name, in one place, for every user-facing string in the Mac app.
let productName = "Notchi"
let brokeReason = "sleeping: compute budget empty"

// yoctoNEAR string to "0.0192 NEAR": 4 decimals, rounded down so the popover never shows more than the account holds.
func near4(_ yocto: String?) -> String {
    guard let yocto, !yocto.isEmpty, yocto.allSatisfy({ $0.isASCII && $0.isNumber }), var units = Decimal(string: yocto) else { return "\u{2014}" }
    units /= Decimal(sign: .plus, exponent: 20, significand: 1)
    var whole = Decimal()
    NSDecimalRound(&whole, &units, 0, .down)
    let digits = String(repeating: "0", count: max(0, 5 - "\(whole)".count)) + "\(whole)"
    return "\(digits.dropLast(4)).\(digits.suffix(4)) NEAR"
}

func nearAmount(_ yocto: Decimal) -> String { "\(yocto / Decimal(sign: .plus, exponent: 24, significand: 1)) NEAR" }

// "+0.0002 NEAR" when the balance went up, nil otherwise (first poll, unknown, same or down).
func nearGain(_ old: String?, _ new: String?) -> String? {
    guard let o = old.flatMap({ Decimal(string: $0) }), let n = new.flatMap({ Decimal(string: $0) }), n > o else { return nil }
    return "+" + nearAmount(n - o)
}

// Talks to apps/server. Server down means the popover says so; nothing is invented.
final class Backend: NSObject {
    let base = ProcessInfo.processInfo.environment["NOTCHI_SERVER"] ?? "http://localhost:8787"
    let petName = ProcessInfo.processInfo.environment["NOTCHI_PET"] ?? "mochi"
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
    var waited = WaitClock()
    // Hook rotation: the next hook on each new appearance of the sign, and every 45s while it stays up.
    var hookIndex = 0
    var hookSince = Date()
    var signWasUp = false
    // follows the server's auto-optimised order when there is one, plain round robin otherwise
    var currentHook: Int {
        guard let c = campaign, !c.allHooks.isEmpty else { return 0 }
        if let o = c.order, !o.isEmpty { return min(max(o[hookIndex % o.count], 0), c.allHooks.count - 1) }
        return hookIndex % c.allHooks.count
    }
    // Polls overlap (timer + after each think); a late reply must not roll the balance back and re-show a meal.
    var petSent = 0, petApplied = 0
    // Rebuild the popover only when what it shows changes, so a "copied" click survives the 10s polls.
    var shown = ""
    var showingSettings = false
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
    lazy var companions: CompanionController = CompanionController(earner: self.pet, growth: self.growth)
    lazy var growthStack: NSStackView = {
        let s = NSStackView(); s.orientation = .vertical; s.alignment = .leading; s.spacing = 6
        s.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18); return s
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
        pet.onContextChange = { [weak self] in self?.shown = ""; self?.render() }
        growth.pet = pet
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
        item.button?.title = productName
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
        let view: [String: Any] = ["petKey": petName, "campaignId": c.campaignId, "hook": currentHook,
                                   "shownMs": Int(Date().timeIntervalSince(since) * 1000), "unlocked": true, "visible": true, "idleS": Int(idle)]
        print("view: posting campaign \(c.campaignId) hook \(currentHook), sign up \(Int(Date().timeIntervalSince(since)))s")
        request("/impressions", body: ["impressions": [view]]) { data, err in
            if let err { print("view: not sent: \(err)") }
            else { print("view: server answered \(String(decoding: data ?? Data(), as: UTF8.self).prefix(120))") }
            self.refresh()
        }
    }

    @objc func toggle() {
        if popover.isShown { popover.close() } else if let b = item.button {
            showingSettings = false
            shown = ""
            render()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        }
    }

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
                req.setValue(s.key, forHTTPHeaderField: "X-Notchi-Key")
                req.setValue(s.time, forHTTPHeaderField: "X-Notchi-Time")
                req.setValue(s.sig, forHTTPHeaderField: "X-Notchi-Sig")
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
                                   "toolName": hook["tool_name"] ?? "", "notificationType": hook["notification_type"] ?? ""]
        request(petPath + "/think", body: body) { data, err in
            self.thinking = false
            if let err { self.lastThink = "think failed: \(err)" }
            else if let data, let r = try? JSONDecoder().decode(ThinkResult.self, from: data) {
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
            let line = showHooks && !hooks.isEmpty ? hooks[currentHook] + tag : nil
            pet.setSign(privacy.lineAllowed(line) ? line : nil, brand: campaign?.brand ?? "")  // focus, stream, share, 12/hour
        }
        if (paused || pet.egg) && !demoMode {
            pet.setSign(nil)  // paused, or still an egg: no line
        } else if pet.offline && !demoMode {
            // offline: sleeps, no lines, no meals, and says why (spec R2 §6)
            pet.setSign(nil)
            pet.setMood("asleep", reason: offlineReason)
        } else if let i = info, !demoMode { pet.setMood(i.mood, reason: i.moodReason) }
        if showingSettings || showingDemo { return }  // don't rebuild under a dragging slider
        let key = "\(privacy.focus.map { Int($0.remaining(Date()) / 60) } ?? -1)|\(PrivacyController.streamOn)|\(growth.p.meals.count)|\(growth.p.stars)|\(growth.isEgg)|\(String(describing: info))|\(String(describing: campaign))|\(serverError ?? "")|\(lastThink)|\(pet.waiting)|\(pet.skin.name)|\(demoMode)"
        if key == shown { return }
        shown = key
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let gear = NSButton(title: "Settings", target: self, action: #selector(openSettings))
        gear.isBordered = false
        gear.font = .systemFont(ofSize: 12)
        gear.contentTintColor = .secondaryLabelColor
        let names = NSStackView(views: [label(info?.name ?? petName, 15, .semibold),
                                        label(info?.mood.uppercased() ?? "\u{2014}", 11, .medium, accentTextColor(pet.skin), mono: true)])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 2
        names.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let demoButton = NSButton(title: demoMode ? "Demo \u{25CF}" : "Demo", target: self, action: #selector(openDemo))
        demoButton.isBordered = false
        demoButton.font = .systemFont(ofSize: 12)
        demoButton.contentTintColor = demoMode ? .systemRed : .secondaryLabelColor
        let head = NSStackView(views: [avatar(), names, spacer, demoButton, gear])
        head.alignment = .centerY
        head.widthAnchor.constraint(equalToConstant: popoverWidth - 32).isActive = true
        stack.addArrangedSubview(head)
        stack.setCustomSpacing(16, after: head)

        if seeded { stack.addArrangedSubview(label("SEEDED DATA: not real NEAR", 11, .bold, mono: true)) }
        if let e = serverError { stack.addArrangedSubview(label("Server: \(e)", 12, .regular, .secondaryLabelColor)) }
        if let f = privacy.focus {
            stack.addArrangedSubview(row("Focus", "\(Int(f.remaining(Date()) / 60) + 1) min left, lines off, not earning"))
            stack.addArrangedSubview(NSButton(title: "End focus", target: self, action: #selector(endFocusNow)))
        }
        if PrivacyController.streamOn { stack.addArrangedSubview(label("Stream mode: lines off, views not counted", 12, .regular, .secondaryLabelColor)) }
        if let i = info, i.mood == "asleep" || i.mood == "hungry", let why = i.moodReason ?? (i.mood == "asleep" ? brokeReason : nil) {
            stack.addArrangedSubview(label(why, 13, .medium, i.mood == "hungry" ? .systemOrange : .secondaryLabelColor))
        }

        // Bars compare the two balances to each other; there is no fixed "full".
        let earned = info?.walletBalance.flatMap { Decimal(string: $0) }
        let food = info?.computeBalance.flatMap { Decimal(string: $0) }
        let top = max(earned ?? 0, food ?? 0)
        for (name, yocto, value) in [("Earned", info?.walletBalance, earned), ("Compute budget", info?.computeBalance, food)] {
            stack.addArrangedSubview(row(name, near4(yocto) + (name == "Earned" ? tag : "")))
            if let value, top > 0 {
                stack.addArrangedSubview(bar(CGFloat(truncating: (value / top) as NSDecimalNumber)))
            }
        }
        stack.addArrangedSubview(row("Today", "waited \(waited.minutes()) min, \(info.map { "\($0.impressionsToday)" } ?? "\u{2014}") views" + tag))
        if let i = info, let views = i.paidViews {
            stack.addArrangedSubview(row("Paid by brands", "\(near4(i.earnedWei)) for \(views) views" + tag))
        }
        let gp = growth.p
        stack.addArrangedSubview(row(growth.isEgg ? "Egg" : "\(gp.stage)".capitalized, growth.isEgg ? "\(growth.egg.calls) of 50 tool calls" : "\(gp.meals.count) meals, \(gp.stars) stars"))
        stack.addArrangedSubview(NSButton(title: "Closet, stars and certificate", target: self, action: #selector(openGrowth)))
        stack.addArrangedSubview(NSButton(title: "Your pet page and weekly recap", target: self, action: #selector(openPetPage)))

        stack.addArrangedSubview(caption("Now showing"))
        let line = !sponsoredOn ? "Sponsored hooks are off" : inQuietHours() ? "Quiet hours: no hooks until 08:00"
            : (info?.impressionsToday ?? 0) >= dailyViewCap ? "Daily limit reached: no more hooks today"
            : campaign.map { "\"\($0.allHooks.isEmpty ? "\u{2014}" : $0.allHooks[currentHook])\"" } ?? "No active campaign"
        stack.addArrangedSubview(label(line, 15, .medium))
        if sponsoredOn, let c = campaign { stack.addArrangedSubview(label("by \(c.brand)\(tag)", 12, .regular, .secondaryLabelColor)) }

        stack.addArrangedSubview(caption("Last thoughts"))
        let thoughts = info?.lastThoughts.prefix(3) ?? []
        if thoughts.isEmpty { stack.addArrangedSubview(label("none yet", 12, .regular, .secondaryLabelColor)) }
        for t in thoughts { stack.addArrangedSubview(copyButton(t.action.uppercased(), t.requestId)) }
        if let tx = info?.lastThoughts.first(where: { $0.chargeTx != nil })?.chargeTx {
            let b = NSButton(title: "Last AI charge on nearblocks", target: self, action: #selector(openLastCharge))
            b.identifier = NSUserInterfaceItemIdentifier(tx)
            stack.addArrangedSubview(b)
        }

        if pet.waiting {
            let b = NSButton(title: "Approve in terminal", target: self, action: #selector(approveInTerminal))
            b.bezelStyle = .rounded
            b.keyEquivalent = "\r"
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(label("Last think: \(lastThink)", 10, .regular, .tertiaryLabelColor))
        popover.contentSize = stack.fittingSize
    }

    func renderSettings() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let back = NSButton(title: "Back", target: self, action: #selector(closeSettings))
        back.isBordered = false
        back.font = .systemFont(ofSize: 12)
        back.contentTintColor = .secondaryLabelColor
        stack.addArrangedSubview(back)
        stack.addArrangedSubview(label("Settings", 22, .semibold))

        stack.addArrangedSubview(caption("Pet"))
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.autoenablesItems = false
        for sp in Roster.all {
            let lock = speciesLock(sp.id)
            picker.addItem(withTitle: lock.map { "\(sp.name) (unlocks with \($0))" } ?? "\(sp.name), the \(sp.kind)")
            picker.lastItem?.isEnabled = lock == nil || demoMode || sp.id == pet.skin.name
        }
        if let i = Roster.all.firstIndex(where: { $0.id == pet.skin.name }) { picker.selectItem(at: i) }
        picker.target = self
        picker.action = #selector(pickSkin(_:))
        stack.addArrangedSubview(picker)

        let sponsored = NSButton(checkboxWithTitle: "Show sponsored hooks (earn while you wait)", target: self, action: #selector(toggleSponsored(_:)))
        sponsored.state = sponsoredOn ? .on : .off
        let quiet = NSButton(checkboxWithTitle: "Quiet hours (no hooks 22:00\u{2013}08:00)", target: self, action: #selector(toggleQuiet(_:)))
        quiet.state = quietHours ? .on : .off
        for v in feelControls() { stack.addArrangedSubview(v) }
        for v in huntControls() { stack.addArrangedSubview(v) }
        for v in privacyControls() { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(sponsored)
        stack.addArrangedSubview(quiet)
        let spaces = NSButton(checkboxWithTitle: "Show over full-screen apps", target: self, action: #selector(toggleAllDesktops(_:)))
        spaces.state = allDesktops ? .on : .off
        stack.addArrangedSubview(spaces)

        stack.addArrangedSubview(caption("Walk speed"))
        let slider = NSSlider(value: walkSpeed, minValue: 0.5, maxValue: 2, target: self, action: #selector(setWalkSpeed(_:)))
        slider.widthAnchor.constraint(equalToConstant: popoverWidth - 32).isActive = true
        stack.addArrangedSubview(slider)

        stack.addArrangedSubview(caption("Remind me"))
        let remind = NSSegmentedControl(labels: ["Off", "2 min", "5 min", "10 min"], trackingMode: .selectOne, target: self, action: #selector(setReminder(_:)))
        remind.selectedSegment = [0.0, 2, 5, 10].firstIndex(of: reminderMinutes) ?? -1
        stack.addArrangedSubview(remind)

        stack.addArrangedSubview(caption("Home after"))
        let seg = NSSegmentedControl(labels: ["30s", "75s", "180s"], trackingMode: .selectOne, target: self, action: #selector(setHomeAfter(_:)))
        seg.selectedSegment = [30.0, 75, 180].firstIndex(of: homeAfter) ?? -1
        stack.addArrangedSubview(seg)

        let home = NSButton(title: "Send pet home", target: self, action: #selector(sendHome))
        home.bezelStyle = .rounded
        stack.addArrangedSubview(home)
        let demo = NSButton(title: "Demo controls\u{2026}", target: self, action: #selector(openDemo))
        demo.bezelStyle = .rounded
        stack.addArrangedSubview(demo)

        // one click instead of hand-editing ~/.claude/settings.json; other hooks are kept and a backup is written first
        let connected = ClaudeHooks.isConnected
        let hooksButton = NSButton(title: connected ? "Disconnect Claude Code" : "Connect Claude Code", target: self, action: #selector(toggleClaudeHooks))
        hooksButton.bezelStyle = .rounded
        stack.addArrangedSubview(caption(connected ? "Claude Code: connected" : "Claude Code: not connected"))
        stack.addArrangedSubview(hooksButton)

        // pairing ties this Mac's Secure Enclave key to the pet; the owner approves it with their wallet on the web
        if devicePublicKey != nil {
            let pair = NSButton(title: "Pair this Mac with my pet", target: self, action: #selector(pairDevice))
            pair.bezelStyle = .rounded
            stack.addArrangedSubview(pair)
        } else {
            stack.addArrangedSubview(caption("This Mac has no Secure Enclave; views stay unsigned"))
        }
        popover.contentSize = stack.fittingSize
    }

    @objc func openSettings() { showingSettings = true; renderSettings() }

    @objc func openDemo() { showingSettings = false; showingDemo = true; renderDemo() }
    @objc func closeDemo() { showingDemo = false; shown = ""; render() }
    func renderDemo() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let back = NSButton(title: "Back", target: self, action: #selector(closeDemo))
        back.isBordered = false
        back.font = .systemFont(ofSize: 12)
        back.contentTintColor = .secondaryLabelColor
        stack.addArrangedSubview(back)
        stack.addArrangedSubview(label("Demo", 22, .semibold))
        stack.addArrangedSubview(caption("Play any event to see what the pet does. Local only: while demo mode is on there are no AI calls and no paid views."))
        let toggle = NSButton(checkboxWithTitle: "Demo mode", target: self, action: #selector(toggleDemo(_:)))
        toggle.state = demoMode ? .on : .off
        stack.addArrangedSubview(toggle)
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.addItems(withTitles: demoEvents.map { $0.0 })
        picker.selectItem(at: demoPick)
        picker.target = self
        picker.action = #selector(pickDemo(_:))
        stack.addArrangedSubview(picker)
        let play = NSButton(title: "Play", target: self, action: #selector(playDemo))
        play.bezelStyle = .rounded
        play.keyEquivalent = "\r"
        stack.addArrangedSubview(play)
        popover.contentSize = stack.fittingSize
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
        case "demo.eat": pet.eat("+0.0002 NEAR food [demo]")
        case "demo.say": pet.say("On it! Tests look green. [demo]", for: 4)
        case "demo.remind":
            reminders.message = "Claude Code is done and waiting for you [demo]"
            reminders.fire()
        case "trick.backflip": pet.trick(.backflip)
        case "trick.moonwalk": pet.trick(.moonwalk)
        case "demo.tryon":
            // try-on is free and unlimited; earning items comes with the Closet (milestone 5)
            let names = pet.skin.pack.notchi.accessories?.names ?? []
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
    @objc func closeSettings() { showingSettings = false; shown = ""; render() }

    @objc func pickSkin(_ sender: NSPopUpButton) {
        guard Roster.all.indices.contains(sender.indexOfSelectedItem) else { return }
        let sp = Roster.all[sender.indexOfSelectedItem]
        guard speciesLock(sp.id) == nil || demoMode || sp.id == pet.skin.name, let s = loadSkin(id: sp.id) else { return }
        if !demoMode { defaults.set(sp.id, forKey: "skin") }  // a demo preview isn't saved
        pet.setSkin(s)
        shown = ""
        render()
    }


    @objc func setReminder(_ sender: NSSegmentedControl) {
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
        a.messageText = "Show sponsored hooks and earn while you wait?"
        a.informativeText = "While your agent works, the pet can carry one short sponsored line. Brands pay per verified view and the money goes to your pet's wallet. Never during approvals, at most 120 a day, and none at night if you turn on quiet hours in Settings. You can change this any time in Settings."
        a.addButton(withTitle: "Turn on")
        a.addButton(withTitle: "Not now")
        sponsoredOn = a.runModal() == .alertFirstButtonReturn
        defaults.set(sponsoredOn, forKey: "sponsored")
        render()
    }

    @objc func setWalkSpeed(_ sender: NSSlider) { walkSpeed = sender.doubleValue; defaults.set(walkSpeed, forKey: "walkSpeed") }

    @objc func setHomeAfter(_ sender: NSSegmentedControl) {
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
        renderSettings()
    }
    @objc func openLastCharge(_ sender: NSButton) {
        let explorer = info?.explorer ?? "https://testnet.nearblocks.io"
        if let tx = sender.identifier?.rawValue, let u = URL(string: "\(explorer)/txns/\(tx)") { NSWorkspace.shared.open(u) }
        popover.close()
    }
    @objc func openPetPage() {
        let web = ProcessInfo.processInfo.environment["NOTCHI_WEB"] ?? "http://localhost:3000"
        let pet = petName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? petName
        if let u = URL(string: "\(web)/me?pet=\(pet)") { NSWorkspace.shared.open(u) }
        popover.close()
    }
    @objc func pairDevice() {
        guard let key = devicePublicKey else { return }
        let web = ProcessInfo.processInfo.environment["NOTCHI_WEB"] ?? "http://localhost:3000"
        let pet = petName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? petName
        if let u = URL(string: "\(web)/pair?pet=\(pet)&key=\(key)") { NSWorkspace.shared.open(u) }
    }

    // Brings the terminal running Claude Code forward. The approval itself happens there; the app never answers a hook.
    @objc func approveInTerminal() {
        let ids = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.apple.Terminal", "com.microsoft.VSCode"]
        let app = ids.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
        app?.activate()
        popover.close()
    }

    @objc func copyId(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        sender.attributedTitle = NSAttributedString(string: "COPIED  " + short(id), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
    }

    func short(_ id: String) -> String { id.count > 20 ? "\(id.prefix(10))\u{2026}\(id.suffix(8))" : id }

    // Shows a shortened ID; clicking copies the full one.
    func copyButton(_ tag: String, _ id: String) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(copyId(_:)))
        b.isBordered = false
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.toolTip = id
        b.attributedTitle = NSAttributedString(string: tag + String(repeating: " ", count: max(1, 11 - tag.count)) + short(id), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
        return b
    }

    func avatar() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.contents = (pet.skin.strips[.idle] ?? pet.skin.strips[.walk])?.frames.first
        v.layer?.contentsGravity = .resizeAspect
        v.layer?.magnificationFilter = .nearest
        v.widthAnchor.constraint(equalToConstant: 44).isActive = true
        v.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return v
    }

    func bar(_ fraction: CGFloat) -> NSView {
        let w = popoverWidth - 32
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        let fill = CALayer()
        fill.backgroundColor = NSColor.labelColor.withAlphaComponent(0.78).cgColor
        fill.frame = CGRect(x: 0, y: 0, width: w * min(max(fraction, 0), 1), height: 2)
        v.layer?.addSublayer(fill)
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        v.heightAnchor.constraint(equalToConstant: 2).isActive = true
        return v
    }

    func caption(_ text: String) -> NSTextField {
        let c = label(text.uppercased(), 10, .medium, .tertiaryLabelColor, mono: true)
        return c
    }

    func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = mono ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.preferredMaxLayoutWidth = popoverWidth - 32
        return l
    }

    func row(_ key: String, _ value: String) -> NSStackView {
        let k = label(key, 13, .regular, .secondaryLabelColor)
        let v = label(value, 15, .semibold)
        v.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [k, spacer, v])
        row.alignment = .firstBaseline
        row.widthAnchor.constraint(equalToConstant: popoverWidth - 32).isActive = true
        return row
    }
}

assert(nearGain("1000000000000000000000000", "1000200000000000000000000") == "+0.0002 NEAR")
assert(nearGain("123456789012345678901234567", "123456789012345678901234568") == "+0.000000000000000000000001 NEAR")
assert(near4("19279999998320000000000") == "0.0192 NEAR" && near4("0") == "0.0000 NEAR" && near4("1000000000000000000000000000") == "1000.0000 NEAR")
assert(near4("99999999999999999999") == "0.0000 NEAR" && near4(nil) == "\u{2014}")
assert(near4("-5") == "\u{2014}" && near4("0x1f") == "\u{2014}" && near4(" 5") == "\u{2014}" && near4("") == "\u{2014}")
assert(!staysHome(mood: "hungry", agentWorking: true) && !staysHome(mood: "hungry", agentWorking: false), "a hungry pet still shows the sign")
assert(!staysHome(mood: "asleep", agentWorking: true) && staysHome(mood: "asleep", agentWorking: false), "only an idle, asleep pet stays home")
assert(!staysHome(mood: "thriving", agentWorking: true) && !staysHome(mood: "stable", agentWorking: false))
assert(nearGain("5", "5") == nil && nearGain("5", "4") == nil && nearGain(nil, "5") == nil)
do { // WaitClock: prompt to stop counts, a lost stop is capped, a new prompt closes the open stretch
    var w = WaitClock(); let t0 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! // away from midnight
    w.handle("UserPromptSubmit", at: t0); w.handle("PreToolUse", at: t0 + 60); w.handle("Stop", at: t0 + 120)
    assert(w.minutes(at: t0 + 130) == 2)
    w.handle("UserPromptSubmit", at: t0 + 200); w.handle("UserPromptSubmit", at: t0 + 200 + 7200)
    assert(w.minutes(at: t0 + 200 + 7200) == 62)
}
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
applyTheme()
guard let skin = loadSkin() else { exit(1) }
let door = Door(art: skin.doors, scale: skin.scale, accent: skin.accent)
let pet = Pet(skin: skin, door: door)
let backend = Backend(pet: pet)
let server: HookServer
do {
    server = try HookServer(port: 47474) { hook in
        backend.run.event(hook, approvalsAnswered: backend.broker.approvalsAnswered)
        backend.growth.hook(hook)
        backend.hunt.hook(hook)
        if backend.companions.route(hook) { backend.render(); return }  // another agent's companion took it
        backend.broker.sawEvent(session: hook["session_id"] as? String ?? "", tool: hook["tool_name"] as? String, event: hook["hook_event_name"] as? String ?? "")
        // the command text never leaves the Mac: it only picks the prop (and, later, spots test runs)
        pet.handle(event: hook["hook_event_name"] as! String, notification: hook["notification_type"] as? String,
                   tool: hook["tool_name"] as? String, command: (hook["tool_input"] as? [String: Any])?["command"] as? String)
        backend.waited.handle(hook["hook_event_name"] as! String)
        backend.think(hook)
        backend.reminders.handle(hook)
        backend.render()
    }
    server.onPermission = { payload, reply in backend.broker.receive(payload, reply: reply) }
    server.onGit = { e in backend.hunt.git(e) }
} catch {
    print("cannot listen on 47474: \(error)")
    exit(1)
}
_ = backend.live  // the notch panel
_ = backend.privacy  // detectors, hot keys, stream mode
print("\(productName) running, hooks on 127.0.0.1:47474, home after \(Int(homeAfter))s")
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { backend.askSponsoredOnce() }
ClaudeHooks.refreshScriptIfStale()
app.run()
