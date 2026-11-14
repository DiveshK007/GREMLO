import GremloCore
import AppKit
import CryptoKit
import Network
import UserNotifications
import os

let petLog = Logger(subsystem: "app.gremlo.mac", category: "pet")

// The pet: sprites, paths, the state machine and the sign (moved out of main.swift unchanged).

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
    var signSponsored = true
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
    var flungHome = false, homing = false
    /// Called when a pet thrown out of the notch has climbed back in.
    var onHome: (() -> Void)?
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

    // A companion may perch on its agent's window: the window's top edge becomes its floor (spec D §4).
    var perch: CGRect? {
        didSet {
            guard perch != oldValue, path == .floor else { return }
            if let p = perch, abs(p.maxY - (oldValue?.maxY ?? p.maxY)) < 400, oldValue != nil { pos.y = floorY; pos.x = min(max(pos.x, leftX), rightX) }  // follows a dragged window
            else { vy = 0; go(.falling); afterLanding = .walk }  // the window went away (or appeared): drop to the new floor
        }
    }
    /// Floor, walls, ceiling and door from GremloCore's HomePath, so the tested geometry is the one on screen.
    var home: HomePath {
        let s = door.host ?? mainScreen
        return HomePath(screen: s.frame, visible: s.visibleFrame, sprite: size, footPadding: skin.footPadding)
    }
    /// Ears up while the Mac's own volume overlay is showing.
    var perkUntil = Date.distantPast
    private var ledgeFrom = Date.distantPast
    private var stepAt = Date.distantPast
    var floorY: CGFloat { perch.map { $0.maxY - skin.footPadding } ?? home.floorY }
    var topY: CGFloat { home.ceilingY }
    var leftX: CGFloat { home.walls(perch: perch).left }
    var rightX: CGFloat { home.walls(perch: perch).right }
    /// Walk to an x and then do something (catching a bug). Cleared by anything that takes the pet off the floor.
    var target: (x: CGFloat, done: () -> Void)?
    var doorX: CGFloat { home.doorX(doorCenterX: door.center.x) }

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
        if p != path { logPath(to: p) }
        let was = path
        path = p
        // notch feel #10: thrown out of the notch, it sits 1.8 s where it lands, walks home and climbs in
        if p == .floor, was != .floor, flungHome {
            flungHome = false
            homing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self, self.path == .floor, self.homing else { return }
                self.goHome(lock: false)
            }
        }
        if p == .home, was != .home, homing { homing = false; onHome?() }
    }

    /// Notch feel #10: the user drags the pet out of the room; it's held at the cursor until let go.
    func grabFromNotch(at mouse: NSPoint) {
        guard path == .home, !egg else { return }
        pos = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        grabOffset = CGPoint(x: size.width / 2, y: size.height / 2)
        dragSamples = [(Date(), mouse)]
        body = nil
        panel.setFrameOrigin(pos)
        panel.orderFrontRegardless()
        door.open()
        flungHome = true
        go(.held)
        set(.grabbed)
        Feel.haptic(.snap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.door.close(lock: false) }
    }

    /// One line per path change, for the home trip (toWall, climbing, ceiling, entering): where the sprite is going,
    /// where the window really is, the row and frame drawn, and whether macOS shows it. Also in Console:
    /// log stream --predicate 'subsystem == "app.gremlo.mac" AND category == "pet"'
    func logPath(to p: Path) {
        let f = panel.frame
        let line = "path \(path.rawValue) -> \(p.rawValue): sprite at \(Int(pos.x)),\(Int(pos.y)) window \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))"
            + " row \(strip.row.rawValue) frame \(sheetFrame) visible \(panel.isVisible) alpha \(panel.alphaValue) occluded \(!panel.occlusionState.contains(.visible))"
            + " level \(panel.level.rawValue) inside \(home.keepsInside(pos)) screen \(Int(mainScreen.frame.width))x\(Int(mainScreen.frame.height)) top \(Int(mainScreen.visibleFrame.maxY))"
        print(line)
        petLog.notice("\(line, privacy: .public)")
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

    func perk() { perkUntil = Date().addingTimeInterval(1.8) }

    /// The display under the pet. A screen with no camera housing becomes its home: a pill on that top edge.
    func screenUnderPet() -> NSScreen {
        let p = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        return NSScreen.screens.first { $0.frame.contains(p) } ?? mainScreen
    }

    func goHome(lock: Bool) {
        if egg && path != .home {  // an egg can't climb: it pops back behind the door
            go(.home); panel.orderOut(nil); door.close(lock: lock); return
        }
        lockWhenHome = lock
        switch path {
        case .home: if lock { door.close(lock: true) }
        case .floor:
            door.place(on: screenUnderPet())
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
                panel.setFrameOrigin(pos)
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
            if let t = target {
                let dx = t.x - (pos.x + size.width / 2)
                if abs(dx) < 6 { target = nil; t.done() }
                else {
                    dir = dx > 0 ? 1 : -1
                    if state != .chase { set(.chase) }
                    pos.x = min(max(pos.x + dir * 120 * dt, leftX), rightX)
                    if pos.x == leftX || pos.x == rightX { target = nil; t.done() }
                }
            } else if state == .chase {
                set(.walk)  // the bug is gone (or the pet was picked up mid-chase)
            } else if state == .walk || state == .sign {
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
            // The sprite stays below the menu bar (HomePath, tested). At the ledge it flips upright, or scrambles
            // straight into the mouth when the door is close.
            if pos.y >= topY {
                pos.y = topY
                dir = -1
                set(.walk)
                if pos.x - doorX <= NotchFeel.scrambleReach {
                    door.open()
                    go(.entering)
                } else {
                    ledgeFrom = Date()
                    go(.ceiling)
                }
            }
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
        if [.floor, .toWall, .climbing, .ceiling].contains(path), [.walk, .climb, .sign].contains(state), Date() >= stepAt {
            stepAt = Date().addingTimeInterval(0.34)
            let span = max(home.screen.width, 1)
            let pan = Float((pos.x + size.width / 2) / span * 2 - 1)
            SoundKit.shared.play(.tick, pan: pan, gain: 0.22)
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

    // The door's window is ordered in once at launch and never out, so it marks Gremlo's home Space.
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

    /// `you`: a bubble from the CLI or a shortcut is outlined and tagged "you" (model bubbles are filled).
    func setBubble(_ text: String, you: Bool = false) {
        bubbleLabel.stringValue = you ? "you: \(text)" : text
        bubbleLabel.backgroundColor = you ? NSColor(white: 0.97, alpha: 1) : .white
        bubbleLabel.wantsLayer = true
        bubbleLabel.layer?.borderWidth = you ? 1.5 : 0
        bubbleLabel.layer?.borderColor = NSColor.black.cgColor
        bubbleLabel.preferredMaxLayoutWidth = 220
        bubbleLabel.frame.size = bubbleLabel.fittingSize
        bubblePanel.setContentSize(bubbleLabel.frame.size)
    }

    func say(_ text: String, for seconds: TimeInterval, you: Bool = false) {
        setBubble(text, you: you)
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
    /// `sponsored: false` is a teammate's visit plate: no AD tab, never an ad.
    func setSign(_ text: String?, brand: String = "", sponsored: Bool = true) {
        let text = text ?? ""
        guard text != signText || brand != signBrand || sponsored != signSponsored else { return }  // render() calls this every poll
        signText = text
        signBrand = brand
        signSponsored = sponsored
        renderPlate()
        let label = text.isEmpty ? "" : sponsored ? "Sponsored, \(brand.isEmpty ? "a brand" : brand): \(text)" : "\(brand): \(text)"
        signPanel.contentView?.setAccessibilityLabel(label)
        signPanel.contentView?.setAccessibilityRole(.button)
        signClick.toolTip = text.isEmpty || !sponsored ? nil : "Sponsored by \(brand.isEmpty ? "a brand" : brand).\nWhy this line: brands pay for real views while your agent works, and that pays for your pet's thinking."
    }

    func renderPlate() {
        guard !signText.isEmpty, let kit = skin.pack.gremlo.signKit, let kitImage = skin.loaded.kit else { plate = nil; return }
        let backing = mainScreen.backingScaleFactor
        guard let (image, layout) = PlateRenderer.render(line: signText, kitImage: kitImage, kit: kit, scale: skin.scale, backing: backing, sponsored: signSponsored) else { plate = nil; return }
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
        // The trip home walks the top edge right side up, facing the notch. It does not flip onto the ceiling.
        // v6 climb frames are pre-rotated for the right wall; walk standing in for climb is turned onto it.
        if strip.rotated { t = t.rotated(by: .pi / 2) }
        // One short flip from the wall onto the ledge, then the walk is upright.
        if path == .ceiling {
            let u = min(1, Date().timeIntervalSince(ledgeFrom) / NotchFeel.ledgeFlip)
            if u < 1 { t = t.rotated(by: (1 - u) * .pi / 2) }
        }
        if path == .floor, Date() < perkUntil {
            t = t.translatedBy(x: 0, y: 3).scaledBy(x: 0.96, y: 1.08)
        }
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
            guard let item = wear[slot], let sheet = skin.pack.gremlo.accessories, let img = skin.loaded.accessory(item),
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
        case .ceiling: pos.y = topY
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
