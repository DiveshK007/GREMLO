import AppKit
import IOKit.ps
import Network
import NotchiCore

// Pets alive (spec R2 §3-6) on the Mac: the idle scheduler, gaze, grab and throw, night, battery, offline, the
// first-session signature move and tool props. The rules live in NotchiCore (Alive.swift) and are unit-tested;
// this file only feeds them the clock, the cursor and the system state.

let offlineReason = "Can't reach the network · sleeping safely"
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

extension Pet {
    // MARK: Context monitors

    func startContextMonitors() {
        network.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.setOffline(path.status != .satisfied) }
        }
        network.start(queue: DispatchQueue(label: "notchi.network"))
        readPower()
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.readPower() })
    }

    /// A companion going away for good: stop its timers and monitors and take its windows down.
    func retire() {
        timers.forEach { $0.invalidate() }
        network.cancel()
        for w in [panel, signPanel, bubblePanel, door.panel] { w.orderOut(nil) }
    }

    func setOffline(_ off: Bool) {
        guard off != offline else { return }
        offline = off
        print(off ? "network: offline, sleeping safely" : "network: back")
        if off { Feel.event("offline") }
        onContextChange?()
    }

    /// IOKit power sources: on battery below 20% the pet slows down; below 10% it goes home and sleeps; plugged
    /// back in after that, one hop.
    func readPower() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        var percent: Int?, onBattery = false
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 { percent = cur * 100 / max }
            onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
        }
        let p = Context.power(percent: percent, onBattery: onBattery)
        guard p != power else { return }
        let was = power
        power = p
        print("power: \(p) (\(percent.map { "\($0)%" } ?? "no battery"), \(onBattery ? "on battery" : "plugged in"))")
        if p == .critical { goHome(lock: false) }
        if was != .normal && p == .normal && path == .floor && !busy { set(.greet, then: state) }  // one hop
    }

    // MARK: The idle scheduler and naps (spec R2 §3)

    var quiet: Quiet { Quiet(holdingLine: state == .sign && plate != nil, approvalWaiting: waiting, inMeeting: false, screenShared: false) }

    /// Called every tick on the floor.
    func aliveTick(now: Date) {
        if Context.isNight(now) != night { night.toggle(); if state == .idle || state == .night { set(night ? .night : .idle) } }
        let day = SeededRNG.daySeed(now)
        if day != schedulerDay { schedulerDay = day; scheduler = IdleScheduler(now: now, seed: day) }
        let free = (state == .walk || state == .idle || state == .night) && !busy && !working
        if free, let micro = scheduler.next(now: now, quiet: quiet) {
            switch micro {
            case .sit: sit(for: power == .low ? 8 : 4)
            case .yawn: if power == .low { sit(for: 8) } else { set(.yawn, then: state); Feel.event("yawn") }
            }
        }
        if free && !napping && IdleScheduler.shouldNap(idleFor: now.timeIntervalSince(lastAgentEvent), night: night) {
            napping = true
            set(night ? .night : .idle)
            Feel.event("snore")
        }
    }

    func sit(for seconds: TimeInterval) {
        set(.sit)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in if self?.state == .sit { self?.set(.walk) } }
    }

    /// Any agent event wakes the pet; the first session of the day plays the signature move once.
    func agentEvent(_ event: String, tool: String?, command: String?) {
        lastAgentEvent = Date()
        if napping { napping = false; if state == .idle || state == .night { set(.walk) } }
        if event == "UserPromptSubmit" || event == "SessionStart" {
            let last = defaults.object(forKey: "signatureDay") as? Date
            if Context.firstSessionToday(lastSignature: last, now: Date()) {
                defaults.set(Date(), forKey: "signatureDay")
                pendingSignature = true
            }
        }
        if event == "PreToolUse", let tool { currentProp = Tools.prop(tool: tool, command: command) }
        if event == "Stop" || event == "StopFailure" || event == "SessionEnd" { currentProp = nil }
    }

    /// Between lines the earner shows the prop for the tool in use; while it holds a line, only the plate.
    func workingState() -> PetState { plate != nil ? .sign : (currentProp != nil ? .tools : .sign) }

    // MARK: Gaze (spec R2 §1 row 17)

    func updateGaze(mouse: NSPoint, inside: Bool) {
        let moved = mouse != lastMouse
        if moved { lastMouse = mouse; lastMouseMove = Date() }
        guard path == .floor, !inside, !busy, [.walk, .idle, .gaze].contains(state) else { return }
        let centre = NSPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        let dx = mouse.x - centre.x, dist = hypot(dx, mouse.y - centre.y)
        let f = gaze.update(offsetX: dx, distance: dist)
        if let f, Date().timeIntervalSince(lastMouseMove) < Gaze.settle {
            if state != .gaze { beforeGaze = state; set(.gaze) }
            gazeFrame = f
        } else if state == .gaze {
            set(beforeGaze ?? .walk)  // back to idle after 3 s without movement, or out of reach
            beforeGaze = nil
        }
    }

    // MARK: Grab and throw (spec R2 §4)

    func beginGrab(at mouse: NSPoint) {
        guard path == .floor || path == .airborne else { return }
        grabOffset = CGPoint(x: mouse.x - pos.x, y: mouse.y - pos.y)
        dragSamples = [(Date(), mouse)]
        body = nil
        go(.held)
        set(.grabbed)
        Feel.haptic(.snap)
        // the door stays shut while a pet is held; the plate comes down and views stop counting
        door.close(lock: false)
        print("grab: held (plate down, views paused)")
    }

    func drag(to mouse: NSPoint) {
        guard path == .held else { return }
        pos = CGPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y)
        dragSamples.append((Date(), mouse))
        dragSamples = dragSamples.filter { Date().timeIntervalSince($0.0) < 0.1 }
    }

    func release(at mouse: NSPoint) {
        guard path == .held else { return }
        let first = dragSamples.first ?? (Date(), mouse)
        let dt = max(Date().timeIntervalSince(first.0), 1 / 120)
        let vx = (mouse.x - first.1.x) / dt, vy = (mouse.y - first.1.y) / dt
        throws_.append(Date())
        throws_ = throws_.filter { Date().timeIntervalSince($0) <= Physics.sulkWindow }
        switch Physics.release(vx: vx, vy: vy, reduceMotion: reduceMotion) {
        case .fadeInPlace:
            // no flight: fade out, come back on the floor where it was dropped
            pos.x = min(max(pos.x, leftX), rightX)
            NSAnimationContext.runAnimationGroup({ c in c.duration = 0.12; panel.animator().alphaValue = 0 }) { [weak self] in
                guard let self else { return }
                self.pos.y = self.floorY
                self.panel.setFrameOrigin(self.pos)
                self.go(.floor)
                self.set(.walk)
                NSAnimationContext.runAnimationGroup { c in c.duration = 0.12; self.panel.animator().alphaValue = 1 }
            }
        case let .fly(x, y):
            body = Physics.Body(x: pos.x, y: max(pos.y - floorY, 0), vx: x, vy: y)
            go(.airborne)
            set(.thrown)
            Feel.event("throw")
        }
    }

    func airborneTick(dt: CGFloat) {
        guard var b = body else { go(.floor); return }
        let bounces = b.bounces
        Physics.step(&b, dt: dt, minX: leftX, maxX: rightX)
        if b.bounces > bounces && !b.resting && bounces > 0 { Feel.event("bounce") }
        body = b
        pos = CGPoint(x: b.x, y: floorY + b.y)
        if b.resting {
            body = nil
            go(.floor)
            dizzy = b.dizzy
            let after: PetState = Physics.sulks(throws: throws_, now: Date()) ? .annoy : .walk
            if after == .annoy { annoyance = 5; lastPoke = Date() }  // the sulk decays like any annoyance
            set(.land, then: after)
            Feel.event(b.dizzy ? "dizzy" : "land")
            if NSEvent.pressedMouseButtons & 1 != 0 { Feel.haptic(.thud) }  // only if a finger is still on the pad
            print("land: \(b.dizzy ? "dizzy" : "soft")\(after == .annoy ? ", sulking" : "")")
        }
    }

    // MARK: Edge peek (spec R2 §1 row 19)

    /// After a hide ends (screen share, full screen, meeting), slide in from the left screen edge.
    func edgePeekIn() {
        guard path == .floor else { return }
        pos.x = leftX
        set(.edgepeek, then: .walk)
    }

    /// Force press: stage 1 maps pressure onto the land row's squash frames, stage 2 plays celebrate.
    func squish(stage: Int, pressure: Float) {
        guard path == .floor, !busy else { return }
        if stage >= 2 { if state != .celebrate { set(.celebrate, then: .walk) }; squashFrame = nil; return }
        squashFrame = stage == 1 ? (pressure > 0.5 ? 1 : 0) : nil
        if squashFrame != nil, state != .land { set(.land, then: .walk) }
    }

    /// Frames for the rows the app picks itself: gaze by cursor, tools by prop, land dizzy or soft, naps asleep.
    func pickedFrames() -> [Int]? {
        switch state {
        case .gaze: return [gazeFrame]
        case .tools: return [currentProp?.rawValue ?? Prop.terminal.rawValue]
        case .land: if let f = squashFrame { return [f] }; return dizzy ? [0, 1, 2, 3, 4, 5] : [0, 1, 4, 5]
        case .hatch: return [eggFrame]
        case .idle where napping: return Sequence.frames(.idle, count: strip.frames.count, mood: "asleep")
        default: return nil
        }
    }
}

/// Clicks poke; a press held 150 ms or more grabs, drags and throws (spec R2 §4).
final class GrabView: NSView {
    var onClick: (() -> Void)?
    var onGrab: ((NSPoint) -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onRelease: ((NSPoint) -> Void)?
    var onSquish: ((Int, Float) -> Void)?
    private var pressed: Date?
    private var grabbing = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Force press (HAPTICS.md): stage 1 pressure squashes the pet, stage 2 celebrates. The trackpad clicks itself.
    override func pressureChange(with event: NSEvent) { onSquish?(event.stage, event.pressure) }
    override func mouseDown(with event: NSEvent) { pressed = Date(); grabbing = false }
    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        if !grabbing, let p = pressed, Physics.isGrab(pressedFor: Date().timeIntervalSince(p)) { grabbing = true; onGrab?(m) }
        if grabbing { onDrag?(m) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; grabbing = false }
        if grabbing { onRelease?(NSEvent.mouseLocation) } else { onClick?() }
    }
}
