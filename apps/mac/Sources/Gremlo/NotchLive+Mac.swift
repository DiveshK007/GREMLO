import AppKit
import Carbon.HIToolbox
import GremloCore

// Notch Live on the Mac (spec D §5, R2 §9, R3 §2). Rules are in GremloCore/NotchLive.swift; this draws them and
// holds the PermissionRequest hook open until the user answers on a surface. The notch never shows a sponsored line.

/// Holds each PermissionRequest hook connection until the user answers, the terminal answers first, or 105 s pass.
final class ApprovalBroker {
    var queue = ApprovalQueue()
    private var replies: [String: (Data?) -> Void] = [:]
    private var suggestions: [String: [[String: Any]]] = [:]
    var onChange: (() -> Void)?

    func receive(_ payload: [String: Any], reply: @escaping (Data?) -> Void) {
        let id = UUID().uuidString
        let r = ApprovalRequest.from(id: id, payload: payload, now: Date())
        replies[id] = reply
        suggestions[id] = payload["permission_suggestions"] as? [[String: Any]] ?? []
        queue.add(r)
        print("approval: \(r.tool) waiting\(r.risky ? " (risky: click only)" : "")")
        // the script gives up at 110 s; release just before so Claude Code shows its own prompt cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 105) { [weak self] in self?.release(id, why: "timed out") }
        onChange?()
    }

    /// The user's answer. Risky requests only arrive here from a click (keys check shortcutAllowed first).
    func answer(_ id: String, _ a: Answer) {
        guard let reply = replies.removeValue(forKey: id) else { return }
        reply(Decision.json(a, suggestions: suggestions.removeValue(forKey: id) ?? []))
        queue.remove(id)
        approvalsAnswered += 1
        onAnswered?()
        Feel.sound(a == .deny ? "deny" : "allow")
        Feel.haptic(a == .deny ? .deny : .allow)
        print("approval: answered \(a.rawValue) from the notch")
        onChange?()
    }

    /// No decision: Claude Code shows its normal prompt (or has already been answered there).
    func release(_ id: String, why: String) {
        guard let reply = replies.removeValue(forKey: id) else { return }
        reply(nil)
        suggestions.removeValue(forKey: id)
        queue.remove(id)
        print("approval: released (\(why))")
        onChange?()
    }

    func sawEvent(session: String, tool: String?, event: String) {
        for id in queue.sawEvent(session: session, tool: tool, event: event) { release(id, why: "answered in the terminal") }
    }

    var approvalsAnswered = 0
    var onAnswered: (() -> Void)?
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class NotchLiveController: NSObject {
    let panel: NotchPanel
    let broker: ApprovalBroker
    let run: RunTracker
    weak var backend: Backend?
    var state = LiveState.rest
    var pinned = false, hovered = false
    var selected = 0
    var dragging = false
    var toastUntil = Date.distantPast
    var dreamIndex = 0
    var scrubLabel: String?
    private var pressStart: Date?
    private var pressOnControl = false
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var hoverWork: DispatchWorkItem?
    private var placed = NSRect.zero     // the shape's target, in screen points
    private var generation = 0           // a newer transition cancels an older one's content swap
    // Notch feel: the notch is one spring-driven path in a fixed, transparent panel (NotchFeel+Mac.swift).
    let shape = NotchShapeLayer()
    let W = Spring(190), H = Spring(32), R = Spring(12)
    let lean = Spring(0, .lean), squash = Spring(0, .squash), press = Spring(1, .press), openness = Spring(0, .close)
    private var leanGrow: (w: Double, h: Double) = (0, 0)
    private var wasBig = false
    private var swapPending = false      // closing: the old content is fading out, the new waits
    var idleRow: Row?
    var idleUntil = Date.distantPast
    private var idleTimer: Timer?
    private var moveMonitors: [Any] = []
    static let big: Set<LiveState> = [.ticker, .knock, .queue, .room, .stuck, .drop, .done, .quick]
    // phase B: pull, flick, force click, heartbeat
    let pullSpring = Spring(0, .pull)
    var quickOpen = false
    private var dragStart: NSPoint?
    private var dragged = false, overPull = false
    private var dragSamples: [(t: CFTimeInterval, y: CGFloat)] = []
    private var holdWork: DispatchWorkItem?
    private var heartbeat: Timer?
    private var heartbeatStart = Date.distantPast
    var fingerDown = false
    static let leans: Set<LiveState> = [.rest, .think]
    var softRunCents: Int? { (defaults.object(forKey: "softAlertRunCents") as? Int).flatMap { $0 > 0 ? $0 : nil } }
    var softDayCents: Int? { (defaults.object(forKey: "softAlertDayCents") as? Int).flatMap { $0 > 0 ? $0 : nil } }
    /// An amber pulse when spend crosses a user-set amount. It never blocks or stops an agent.
    var softAlert: Bool {
        SoftAlert.due(costMicroCents: run.runUsage.flatMap(Prices.costMicroCents), limitCents: softRunCents)
            || SoftAlert.due(costMicroCents: run.dayMicroCents, limitCents: softDayCents)
    }

    var notchHeight: CGFloat { mainScreen.safeAreaInsets.top > 0 ? mainScreen.safeAreaInsets.top : 0 }

    init(broker: ApprovalBroker, run: RunTracker) {
        self.broker = broker
        self.run = run
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let drop = DropView(frame: .zero)
        panel.contentView = drop
        drop.wantsLayer = true
        drop.layer?.addSublayer(shape)  // the black notch: always black, whatever the theme
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true  // clicks pass through everywhere but the notch itself
        Motion.reduce = reduceMotion
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            Motion.reduce = reduceMotion
        }
        NotchDriver.shared.attach(to: drop)
        NotchDriver.shared.register(W, H, R, lean, squash, press, openness, pullSpring)
        drop.onTouches = { [weak self] n in self?.fingerDown = n > 0 }
        // #11: ⌥⌘N opens or folds the notch from anywhere
        HotKeys.register(3, keyCode: UInt32(kVK_ANSI_N), mods: UInt32(cmdKey | optionKey)) { [weak self] in self?.toggleNotch() }
        NotchDriver.shared.onFrame = { [weak self] in self?.applyFrame() }
        // the pointer, wherever it is (mouse events need no permission): hover, lean and click-through
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) { moveMonitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { moved($0); return $0 }) { moveMonitors.append(l) }
        broker.onChange = { [weak self] in self?.update() }
        drop.onDragging = { [weak self] on in
            guard let self, self.dragging != on else { return }
            self.dragging = on
            // #12: the mouth opens with a snap; leaving without dropping ticks (a drop has its own boop)
            if on { Feel.haptic(.snap) } else if Date() >= self.toastUntil { Feel.haptic(.tick) }
            self.update()
        }
        drop.onScroll = { [weak self] e in self?.scrolled(e) }
        drop.onDropped = { [weak self] in
            self?.toastUntil = Date().addingTimeInterval(2.6)
            SoundKit.shared.play(.chomp)
            Feel.haptic(.boop)  // with the gulp
            self?.update()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) == true ? nil : e }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .pressure]) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            if e.type == .leftMouseDragged { self.dragMoved(); return e }
            if e.type == .pressure { self.pressure(e); return e }
            if e.type == .leftMouseDown {
                self.hoverWork?.cancel()
                self.hovered = true  // a click means the pointer is here, even inside the hover delay
                self.pressStart = Date()
                self.pressOnControl = self.interactive(at: e.locationInWindow)
                // the press dent; a button gives its own feedback, so only a press on the notch itself boops
                self.press.animate(to: NotchFeel.pressScale, .press)
                if !self.pressOnControl { Feel.haptic(.boop) }
                self.dragStart = NSEvent.mouseLocation
                self.dragged = false; self.overPull = false; self.dragSamples = []
                // #9 without Force Touch: holding still opens the quick actions
                self.holdWork?.cancel()
                if !self.pressOnControl {
                    let w = DispatchWorkItem { [weak self] in
                        guard let self, self.pressStart != nil, !self.dragged else { return }
                        self.openQuick()
                    }
                    self.holdWork = w
                    DispatchQueue.main.asyncAfter(deadline: .now() + NotchFeel.quickHold, execute: w)
                }
            } else {
                self.press.animate(to: 1, .release)
                self.mouseUp()
            }
            return e
        }
        // a display plugged in or a resolution change moves the notch
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.layoutPanel()
            self?.place(animated: false)
        }
        layoutPanel()
        place(animated: false)
        panel.orderFrontRegardless()
        let clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        clock.tolerance = 0.2
        scheduleIdleLife()
    }

    // MARK: State

    func inputs() -> NotchLive.Inputs {
        var i = NotchLive.Inputs()
        i.waiting = broker.queue.waiting.count
        i.doneUntil = run.doneUntil
        i.hoverOrPin = (hovered || pinned) && run.started != nil
        i.toolRunning = NotchLive.toolShowing(running: run.toolRunning, lastToolEnd: run.lastToolEnd, runEnded: run.endedAt != nil, now: Date())
        i.thinking = run.thinking
        i.dragging = dragging || Date() < toastUntil
        i.quick = quickOpen
        i.roomOpen = roomOpen
        i.focus = backend?.privacy.focus != nil
        i.stuck = backend?.hunt.stuckTrigger != nil
        i.meetingSoon = backend?.hunt.meetingSoonText != nil
        if let g = backend?.growth { i.egg = g.isEgg && backend?.pet.path != .home || unlockNoteShowing }
        i.sleeping = backend.map { $0.pet.napping || $0.pet.night && $0.pet.path == .home } ?? false
        i.offline = backend?.pet.offline ?? false
        return i
    }

    func update() {
        // the panel can shrink out from under the pointer (an answered approval folds the card), and then no
        // mouseExited comes; without this the run-over ticker stayed up for good instead of folding to rest
        hovered = NotchLive.stillHovered(hovered, pointerInside: hoverWanted(at: NSEvent.mouseLocation) != false,
                                         exitPending: hoverWork.map { !$0.isCancelled } ?? false)
        let s = NotchLive.resolve(inputs(), now: Date())
        if s != state {
            print("notch: \(state.rawValue) -> \(s.rawValue)")
            if state == .ticker { scrubLabel = nil }
            if s != .queue { selected = 0 }
            state = s
            place(animated: true)
            if hovered && needsKeys { panel.makeKey() }
        } else if target() != placed {
            place(animated: true)  // same state, new size: another agent joined the queue, or a note dropped below the notch
        } else {
            refreshContent()
        }
        if !(hovered && needsKeys) { giveBackKeyboard() }
        passThrough()
        SpriteClock.shared.visible = backend?.privacy.duck != .hidden
        heartbeatTick()
    }

    /// Hook events redraw at once (the timer only moves the clock), and done and the peek linger end on time.
    func hooked(_ event: String) {
        update()
        if event == "PostToolUse" || event == "PostToolUseFailure" { wake(after: NotchLive.peekLinger) }
        if event == "Stop" || event == "StopFailure" { wake(after: NotchLive.doneHold) }
    }
    private func wake(after t: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.05) { [weak self] in self?.update() }
    }

    /// Keys do something only with an approval waiting (⌥↩ ⌥⌫ ⌥↓) or the notch held open (esc).
    var needsKeys: Bool { !broker.queue.waiting.isEmpty || pinned || roomOpen }

    /// The panel holds the keyboard only while the pointer is on it. Ordering it out and back hands the keyboard to the
    /// app underneath, so an answer typed in the terminal always lands there (the terminal answer wins).
    func giveBackKeyboard() {
        guard panel.isKeyWindow, NSEvent.pressedMouseButtons == 0 else { return }  // never mid-click on a button
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: Layout and motion

    var unlockNoteShowing: Bool { backend?.growth.unlockNote.map { Date() < $0.until } ?? false }

    /// Tall states open below the camera housing. On a notched Mac a sentence in a short state would sit behind it, so
    /// offline and the new-egg note drop below as well.
    /// Where the shape is heading: the state's size, hover's when the pointer rests on a small notch, idle life's.
    var shapeSize: (w: Double, h: Double) {
        if state == .rest, idleRow != nil, Date() < idleUntil { return NotchFeel.idleSize }
        if hovered, Self.leans.contains(state) { return NotchFeel.hoverSize }
        return NotchLive.size(state, agents: broker.queue.waiting.count)
    }

    var belowNotch: Bool {
        shapeSize.h > 40
            || notchHeight > 0 && (state == .offline || state == .egg && unlockNoteShowing)
    }

    func target() -> NSRect {
        let sz = shapeSize
        let f = mainScreen.frame
        let rest = state == .rest && notchHeight > 0
        let w = rest ? max(CGFloat(sz.w), (mainScreen.auxiliaryTopRightArea.map { f.width - $0.width - (mainScreen.auxiliaryTopLeftArea?.width ?? 0) }) ?? CGFloat(sz.w)) : CGFloat(sz.w)
        let h = CGFloat(sz.h) + (belowNotch ? notchHeight : 0)
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h).integral
    }

    /// The panel stays put: wide and tall enough for the biggest state, centred on the notch, clear everywhere the
    /// shape isn't. Only the path inside it moves.
    func layoutPanel() {
        let f = mainScreen.frame
        let tallest = LiveState.allCases.map { NotchLive.size($0, agents: 4).h }.max() ?? 230
        let h = notchHeight + CGFloat(tallest) + 60   // room for the depth shadow and the glow
        let w: CGFloat = 820
        panel.setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h).integral, display: false)
        shape.frame = panel.contentView?.bounds ?? .zero
        applyFrame()
    }

    /// The shape springs to its new size (the open spring with a tap on the overshoot frame, or the close spring),
    /// squashes, and the content rows stagger in behind it. Closing takes the old content out first (80 ms).
    func place(animated: Bool) {
        generation += 1
        let g = generation, frame = target(), s = state
        let to = (w: Double(frame.width), h: Double(frame.height))
        let opening = NotchFeel.isOpening(from: (W.target, H.target), to: to)
        placed = frame
        contentWidth = CGFloat(NotchLive.size(s, agents: broker.queue.waiting.count).w) - 36
        shape.rimColor = nsColor(hex: s == .done ? NotchFeel.doneColor : s == .stuck ? NotchFeel.failColor : NotchFeel.agentColor(run.agent))
        shape.rimMode = NotchFeel.rim(s)
        let swap = { [weak self] in
            guard let self, g == self.generation else { return }
            self.refreshContent(clear: true, stagger: animated)
            self.spring(to: to, opening: opening, animated: animated)
            if animated && !reduceMotion && s == .knock { self.shake() }
            if animated && s == .done { self.burst(self.run.errors > 0 ? .smoke : .confetti) }
            if animated && s == .stuck { self.burst(.smoke) }
        }
        if animated, !opening, !Motion.reduce, !stack.arrangedSubviews.isEmpty {
            swapPending = true
            NSAnimationContext.runAnimationGroup { c in c.duration = NotchFeel.contentOut; stack.animator().alphaValue = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchFeel.contentOut) { [weak self] in self?.swapPending = false; swap() }
        } else { swapPending = false; swap() }
    }

    private func spring(to: (w: Double, h: Double), opening: Bool, animated: Bool) {
        let big = Self.big.contains(state), r = NotchFeel.radius(state)
        defer { wasBig = big }
        if !Self.leans.contains(state) || hovered {  // only a small notch leans; a stale lean must not ride along
            leanGrow = (0, 0)
            lean.animate(to: 0, .lean)
        }
        guard animated else {
            W.hold(at: to.w); H.hold(at: to.h); R.hold(at: r); openness.hold(at: big ? 1 : 0)
            applyFrame()
            return
        }
        let p: SpringParams = opening ? .open : .close
        // a card opening gets the tap and the pop; the peek coming and going with every tool only moves
        let felt = opening && to.h > 40
        W.animate(to: to.w + leanGrow.w, p, onPeak: felt ? { [weak self] in self?.peakTap() } : nil)
        H.animate(to: to.h + leanGrow.h, p.heavier)
        R.animate(to: r, SpringParams(response: 0.4, damping: 0.9))
        openness.animate(to: big ? 1 : 0, .close)
        if !Motion.reduce { squash.kick(opening ? NotchFeel.squashOpen : NotchFeel.squashClose) }
        if felt { SoundKit.shared.play(.pop) } else if wasBig && !big { SoundKit.shared.play(.close) }
    }

    /// #19: the snap lands with the frame that shows the overshoot.
    private func peakTap() {
        Feel.haptic(.snap, at: .drawCompleted)
        #if DEBUG
        print("notch: peak haptic on frame \(NotchDriver.shared.frame), width \(String(format: "%.1f", W.value)) for a target of \(String(format: "%.0f", W.target))")
        #endif
    }

    /// Every display frame while something moves: the springs onto the path.
    func applyFrame() {
        guard let b = panel.contentView?.bounds, b.width > 0 else { return }
        if shape.frame != b { shape.frame = b }
        let g = NotchGeometry(width: W.value, height: H.value + max(0, pullSpring.value), radius: R.value, bulge: max(0, -squash.value) / 2.2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // also when called outside the frame clock (layout, a jump)
        shape.apply(g, centerX: b.midX + lean.value, top: b.maxY, squash: Motion.reduce ? 0 : squash.value, press: press.value, open: openness.value)
        CATransaction.commit()
    }

    /// The shape on screen right now (springs, not targets), so clicks land on what you see.
    var shapeOnScreen: NSRect {
        let f = mainScreen.frame
        let h = H.value + max(0, pullSpring.value)
        return NSRect(x: f.midX + lean.value - W.value / 2, y: f.maxY - h, width: W.value, height: h)
    }

    /// Clicks pass through the panel everywhere except the notch, so the menu bar and the windows under it still work.
    func passThrough() {
        if pressStart != nil { if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }; return }  // mid-press: keep the drag
        let over = shapeOnScreen.union(placed).insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    /// true: the pointer wants hover (on the shape, or within 34 pt of the notch's top centre); false: it's gone
    /// (off the shape and 70 pt away); nil: in between, so nothing changes.
    func hoverWanted(at p: NSPoint) -> Bool? {
        let f = mainScreen.frame
        let l = NotchFeel.lean(dx: p.x - f.midX, dy: f.maxY - p.y)
        let on = placed.insetBy(dx: -6, dy: -6).contains(p)
        if on || l.distance < NotchFeel.hoverEnter { return true }
        if l.distance > NotchFeel.hoverLeave { return false }
        return nil
    }

    /// #4: the notch leans toward a nearby cursor and swells a little; hover comes and goes by distance.
    func pointerMoved() {
        let p = NSEvent.mouseLocation
        passThrough()
        switch hoverWanted(at: p) {
        case true?: if !hovered { hover(true, after: 0.12) }
        case false?: if hovered { hover(false, after: 0.3) }
        case nil: break
        }
        let f = mainScreen.frame
        let l = Self.leans.contains(state) && !Motion.reduce ? NotchFeel.lean(dx: p.x - f.midX, dy: f.maxY - p.y) : NotchFeel.lean(dx: 0, dy: 1000)
        let grow = hovered ? (w: 0.0, h: 0.0) : (w: Double(l.growW), h: Double(l.growH))  // hover is its own size
        guard abs(l.shift - lean.target) > 0.25 || abs(grow.w - leanGrow.w) > 0.5 else { return }  // far away: no frames
        leanGrow = grow
        lean.animate(to: l.shift, .lean)
        let sz = target()
        W.animate(to: Double(sz.width) + grow.w, .lean)
        H.animate(to: Double(sz.height) + grow.h, .lean)
    }

    // MARK: Idle life (#16)

    func scheduleIdleLife() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: .random(in: NotchFeel.idleEvery), repeats: false) { [weak self] _ in
            guard let self else { return }
            if NotchFeel.idleAllowed(state: self.state, screenShared: silence.screenShared, inMeeting: silence.inMeeting, focus: self.backend?.privacy.focus != nil),
               !Motion.reduce {
                self.idleRow = NotchFeel.idleRow(hour: Calendar.current.component(.hour, from: Date()), pick: Int.random(in: 0..<4))
                self.idleUntil = Date().addingTimeInterval(NotchFeel.idleHold)
                self.place(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchFeel.idleHold + 0.05) { [weak self] in
                    self?.idleRow = nil
                    self?.update()
                }
            }
            self.scheduleIdleLife()
        }
        idleTimer?.tolerance = 3
    }

    func shake() {
        guard let layer = panel.contentView?.layer else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -8, 8, -6, 6, -3, 3, 0]
        a.duration = 0.55
        layer.add(a, forKey: "knock")
    }

    /// #14: a burst from the notch's bottom edge, 120 ms of birth, gone after 2.6 s. Capped by the budget, none under
    /// Reduce Motion.
    func burst(_ kind: NotchFeel.Burst) {
        guard !Motion.reduce, let root = panel.contentView?.layer else { return }
        let b = root.bounds, w = CGFloat(W.target), bottom = b.maxY - CGFloat(H.target)
        Particles.burst(kind, in: root, at: CGPoint(x: b.midX, y: bottom + 4), width: max(20, w - 12),
                        count: NotchFeel.particles(kind, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled),
                        palette: Roster.all.map { nsColor(hex: $0.accent) })
    }

    // MARK: Content

    private var stack = NSStackView()
    /// Live values (clock, cost, counts, bars) set in place on every refresh; views are rebuilt only when the layout changes.
    private var ticks: [() -> Void] = []
    private var contentWidth: CGFloat = 154
    var lastKey = ""
    var roomOpen = false
    private var pull: CGFloat = 0
    private var swipe: CGFloat = 0

    /// What decides the layout. Everything else is a live value, so buttons are never recreated under the pointer
    /// and the pulse and the breathing edge don't restart every second.
    var layoutKey: String {
        "\(state)|\(broker.queue.waiting.map(\.id))|\(selected)|\(pinned)|\(dragging)|\(softAlert)|\(run.endedAt != nil && !run.steps.isEmpty)"
            + "|\(backend?.hunt.stuckTrigger?.line ?? "")|\(unlockNoteShowing)|\(backend?.privacy.focus != nil)|\(idleRow != nil && Date() < idleUntil)"
    }

    func refreshContent(clear: Bool = false, stagger: Bool = false) {
        let key = layoutKey
        if !clear && (key == lastKey || swapPending) { ticks.forEach { $0() }; return }
        lastKey = key
        ticks = []
        stack.removeFromSuperview()
        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: notchHeight > 0 && belowNotch ? notchHeight + 6 : 8, left: 18, bottom: 10, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alphaValue = 1
        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        // centred at the final width, so the content stays put while the shape blooms around it
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                                     stack.widthAnchor.constraint(equalToConstant: contentWidth + 36),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor)])
        switch state {
        case .egg:
            if unlockNoteShowing, let n = backend?.growth.unlockNote { stack.addArrangedSubview(text(n.text, 11, .primary)) }
            else if let g = backend?.growth {
                let calls = text("", 11, .secondary, mono: true)
                stack.addArrangedSubview(row([eyes(), spacer(), calls]))
                ticks.append { calls.stringValue = "egg \u{00B7} \(g.egg.calls)/50" }
            }
        case .drop:
            // #12 the mouth: the gulp row's first frame open while dragging, the whole gulp once it's eaten
            let gulp = backend?.pet.skin.loaded.strip(.gulp)?.frames ?? []
            let pet = SpriteView(frames: dragging ? Array(gulp.prefix(1)) : gulp, size: 44)
            stack.addArrangedSubview(row([pet, text(dragging ? "Drop to copy the path" : "Ready to paste", 13, .primary), spacer()]))
        case .quick: quickCard()
        case .meeting:
            let soon = text("", 11, .secondary, mono: true)
            stack.addArrangedSubview(row([eyes(), spacer(), soon]))
            ticks.append { [weak self] in soon.stringValue = self?.backend?.hunt.meetingSoonText ?? "" }
        case .stuck: if let t = backend?.hunt.stuckTrigger { stuckCard(t) }
        case .room: if let b = backend { room(b) }
        case .focus:
            let (dial, arc) = ring()
            let label = text("", 11, .secondary, mono: true)
            stack.addArrangedSubview(row([dial, spacer(), label]))
            ticks.append { [weak self] in
                guard let f = self?.backend?.privacy.focus else { return }
                arc.strokeEnd = f.progress(Date())
                label.stringValue = "focus \(f.label(Date()))"
            }
        case .rest:
            if let r = idleRow, Date() < idleUntil, let frames = backend?.pet.skin.loaded.strip(r)?.frames {
                stack.addArrangedSubview(row([SpriteView(frames: frames, size: 30), spacer()]))
            }
        case .visitor: break
        case .think: break  // the flowing rim says it
        case .peek: stack.addArrangedSubview(row([eyes(), spacer(), softAlert ? text("over your cost alert", 10, .amber) : pulse()]))
        case .sleep:
            let icon = dreamIcon()
            stack.addArrangedSubview(row([eyes(asleep: true), spacer(), icon]))
            ticks.append { [weak self] in self?.showDream(in: icon) }
        case .offline: stack.addArrangedSubview(text("Can't reach the network \u{00B7} sleeping safely", 12, .primary))
        case .ticker: ticker()
        case .done: done()
        case .knock: if let r = broker.queue.top { knock(r) }
        case .queue: queueRows()
        }
        ticks.forEach { $0() }
        if stagger { Stagger.rows(stack.arrangedSubviews) }
    }

    func ticker() {
        let tool = text("", 13, .primary, mono: true)
        let line = RollingLabel(size: 11, color: color(.secondary)), cost = RollingLabel(size: 11, color: color(.secondary))
        stack.addArrangedSubview(row([tool, spacer(), text(run.agent, 11, .secondary)]))
        stack.addArrangedSubview(row([line, spacer(), cost]))
        ticks.append { [weak self] in
            guard let self else { return }
            tool.stringValue = self.run.lastTool.isEmpty ? "waiting" : self.run.lastTool
            line.stringValue = self.scrubLabel ?? "\(self.run.tools) tools \u{00B7} \(self.clock(self.run.elapsed))"
            cost.stringValue = Prices.label(self.run.runUsage)
            cost.color = self.color(self.softAlert ? .amber : .secondary)
        }
        if run.endedAt != nil && !run.steps.isEmpty {
            let scrub = ScrubView()
            scrub.steps = run.steps
            if let a = backend?.pet.skin.accent { scrub.accent = NSColor(cgColor: a) ?? .white }
            scrub.onHover = { [weak self] s in self?.scrubLabel = s; self?.refreshContent() }  // a live value: the scrubber stays under the pointer
            scrub.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            scrub.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(scrub)
        } else {
            // #15 the progress scene: no ETA is known, so the pet walks in place at the start of the track and the
            // track pulses; never a made-up percentage
            let walker = SpriteView(frames: backend?.pet.skin.loaded.strip(.walk)?.frames ?? [], size: 18)
            let b = bars(width: contentWidth - 26)
            if !Motion.reduce {
                b.wantsLayer = true
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1; a.toValue = 0.6; a.duration = 0.9; a.autoreverses = true; a.repeatCount = .infinity
                b.layer?.add(a, forKey: "pulse")
            }
            stack.addArrangedSubview(row([walker, b]))
            ticks.append { [weak self] in self?.drawBars(in: b) }
        }
    }

    /// A two-finger pull down on the notch opens the room; a pull up closes it.
    func scrolled(_ e: NSEvent) {
        // a sideways swipe moves between waiting agents in the queue
        if state == .queue, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) {
            swipe += e.scrollingDeltaX
            if abs(swipe) > 40 {
                let n = min(broker.queue.waiting.count, 4)
                selected = (selected + (swipe < 0 ? 1 : n - 1)) % max(n, 1)
                let dir: CGFloat = swipe < 0 ? -1 : 1
                swipe = 0
                Feel.haptic(.tick)
                SoundKit.shared.play(.tick)
                refreshContent(clear: true)
                slide(dir * NotchFeel.detentSlide)
            }
            if e.phase == .ended { swipe = 0 }
            return
        }
        let dy = e.isDirectionInvertedFromDevice ? e.scrollingDeltaY : -e.scrollingDeltaY
        pull += dy
        if e.phase == .ended || e.phase == .cancelled || abs(pull) > 40 {
            if pull > 30, !roomOpen { roomOpen = true; Feel.haptic(.snap); update() }
            else if pull < -30, roomOpen { roomOpen = false; update() }
            pull = 0
        }
    }

    /// The content arrives from the side it was scrolled from, on the release spring.
    func slide(_ dx: CGFloat) {
        guard !Motion.reduce else { return }
        stack.wantsLayer = true
        let p = SpringParams.release
        let a = CASpringAnimation(keyPath: "transform.translation.x")
        a.fromValue = dx; a.toValue = 0
        a.mass = 1; a.stiffness = p.stiffness; a.damping = p.dampingCoefficient
        a.duration = a.settlingDuration
        stack.layer?.add(a, forKey: "detent")
    }

    func room(_ b: Backend) {
        let size = NSSize(width: NotchLive.size(.room).w, height: NotchLive.size(.room).h + notchHeight)
        let v = RoomView(backend: b, size: size, top: notchHeight + 4)
        v.widthAnchor.constraint(equalToConstant: size.width - 36).isActive = true
        v.heightAnchor.constraint(equalToConstant: size.height - notchHeight - 18).isActive = true
        stack.addArrangedSubview(v)
    }

    /// The 290 x 36 focus timer ring; the arc is moved by a tick.
    func ring() -> (NSView, CAShapeLayer) {
        let v = NSView()
        v.wantsLayer = true
        let track = CAShapeLayer(), arc = CAShapeLayer()
        let path = CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 18, height: 18), transform: nil)
        for (l, c) in [(track, NSColor(white: 1, alpha: 0.2).cgColor), (arc, backend?.pet.skin.accent ?? NSColor.white.cgColor)] {
            l.path = path; l.fillColor = nil; l.strokeColor = c; l.lineWidth = 3
            v.layer?.addSublayer(l)
        }
        arc.strokeEnd = 0
        v.widthAnchor.constraint(equalToConstant: 22).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return (v, arc)
    }

    func stuckCard(_ t: StuckTrigger) {
        let title = text("", 13, .amber)
        stack.addArrangedSubview(title)
        ticks.append { title.stringValue = StuckDetector.title(t, now: Date()) }
        stack.addArrangedSubview(text(t.line, 12, .primary, mono: true))
        let ignore = NSButton(title: "Ignore this run", target: self, action: #selector(stuckIgnore))
        let nudge = NSButton(title: "Copy a nudge", target: self, action: #selector(stuckNudge))
        let show = NSButton(title: "Show me", target: self, action: #selector(stuckShow))
        stack.addArrangedSubview(row([ignore, nudge, show, spacer()]))
    }
    @objc func stuckIgnore() { backend?.hunt.ignoreRun() }
    @objc func stuckNudge() { backend?.hunt.copyNudge(); Feel.haptic(.tick) }
    @objc func stuckShow() { backend?.approveInTerminal() }

    /// One dream icon per interval from today's events; hover tells what it's dreaming about (R4 §7).
    func dreamIcon() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.contentsGravity = .resizeAspect
        v.layer?.magnificationFilter = .nearest
        v.widthAnchor.constraint(equalToConstant: 18).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }
    func showDream(in v: NSView) {
        dreamIndex = Int(Date().timeIntervalSince1970 / DreamLog.interval)
        let icons = backend?.hunt.dreams.icons ?? []
        let d = icons.isEmpty ? .moon : icons[dreamIndex % icons.count]
        v.layer?.contents = Props.image("d-\(d.rawValue)")
        v.toolTip = backend.map { $0.hunt.dreams.summary(name: $0.growth.petDisplayName) }
    }

    func done() {
        let answered = broker.approvalsAnswered - run.approvalsAtStart
        let cost = RollingLabel(size: 11, color: color(.secondary))
        stack.addArrangedSubview(row([text("Done in \(clock(run.elapsed))", 15, .primary), spacer(), cost]))
        stack.addArrangedSubview(text("\(run.tools) tools \u{00B7} \(answered) approvals \u{00B7} \(run.errors) errors \u{00B7} earned \u{2014}", 11, .secondary))
        ticks.append { [weak self] in cost.stringValue = Prices.label(self?.run.runUsage) }
    }

    func knock(_ r: ApprovalRequest) {
        stack.addArrangedSubview(row([text("Needs approval", 13, .primary), spacer(), text(r.tool, 11, .secondary, mono: true)]))
        stack.addArrangedSubview(text(r.summary.isEmpty ? "—" : r.summary, 12, .primary, mono: true))
        var buttons: [NSView] = [button("Deny", r.id, .deny)]
        if r.canAlwaysAllow { buttons.append(button("Always allow", r.id, .alwaysAllow)) }
        buttons.append(button(r.risky ? "Allow once" : "Allow once  \u{2325}\u{21A9}", r.id, .allowOnce, primary: true))
        let terminal = NSButton(title: "Answer in terminal", target: self, action: #selector(releaseTop))
        terminal.isBordered = false
        terminal.contentTintColor = .secondaryLabelColor
        stack.addArrangedSubview(row(buttons + [spacer(), terminal]))
        if r.risky { stack.addArrangedSubview(text("Deletes, pushes or spends: answer with a click.", 10, .secondary)) }
    }

    func queueRows() {
        let items = Array(broker.queue.waiting.prefix(4))
        for (i, r) in items.enumerated() {
            let mark = i == selected ? "\u{203A} " : "  "
            stack.addArrangedSubview(row([text(mark + r.tool, 12, .primary, mono: true), text(String(r.summary.prefix(60)), 11, .secondary, mono: true), spacer(),
                                          button("Deny", r.id, .deny), button("Allow", r.id, .allowOnce, primary: true)]))
        }
    }

    // MARK: Pieces

    enum Tone { case primary, secondary, amber }
    func color(_ tone: Tone) -> NSColor { tone == .primary ? NSColor(white: 1, alpha: 0.85) : tone == .amber ? .systemOrange : NSColor(white: 1, alpha: 0.55) }
    func text(_ s: String, _ size: CGFloat, _ tone: Tone, mono: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = mono ? .monospacedSystemFont(ofSize: size, weight: .medium) : .systemFont(ofSize: size, weight: size >= 13 ? .semibold : .regular)
        l.textColor = color(tone)
        l.lineBreakMode = .byTruncatingTail
        return l
    }
    func row(_ v: [NSView]) -> NSStackView {
        let r = NSStackView(views: v)
        r.orientation = .horizontal
        r.spacing = 8
        r.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return r
    }
    func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
    func button(_ title: String, _ id: String, _ a: Answer, primary: Bool = false) -> NSButton {
        let b = AnswerButton(title: title, target: self, action: #selector(answered(_:)))
        b.requestId = id
        b.answer = a
        b.bezelStyle = .rounded
        if primary, let accent = backend?.pet.skin.accent { b.bezelColor = NSColor(cgColor: accent); b.keyEquivalent = "" }
        return b
    }
    /// The pet peeking from the notch, on the 8 fps sprite clock (frame 0 under Reduce Motion).
    func eyes(asleep: Bool = false) -> NSView {
        let loaded = backend?.pet.skin.loaded
        let frames = asleep ? Array((loaded?.frames[.idle] ?? []).dropFirst(5).prefix(2)) : (loaded?.frames[.peek] ?? [])
        return SpriteView(frames: frames, size: 26)
    }
    func pulse() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = backend?.pet.skin.accent
        v.layer?.cornerRadius = 4
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        if !reduceMotion {
            let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 1; a.toValue = 0.25; a.duration = 0.8; a.autoreverses = true; a.repeatCount = .infinity
            v.layer?.add(a, forKey: "pulse")
        }
        return v
    }
    func bars(width: CGFloat? = nil) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.widthAnchor.constraint(equalToConstant: width ?? contentWidth).isActive = true
        v.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return v
    }
    func drawBars(in v: NSView) {
        let w = v.bounds.width > 0 ? v.bounds.width : contentWidth
        let accent = backend?.pet.skin.accent ?? NSColor.white.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        v.layer?.sublayers = run.activity.suffix(48).enumerated().map { i, c in
            let b = CALayer()
            let h: CGFloat = c == "x" ? 12 : c == "e" ? 9 : c == "r" ? 6 : 14
            b.backgroundColor = c == "f" ? NSColor.systemRed.cgColor : c == "a" ? NSColor.white.cgColor : accent.copy(alpha: c == "p" ? 1 : 0.7)
            b.frame = CGRect(x: CGFloat(i) * (w / 48), y: 0, width: max(2, w / 48 - 2), height: h)
            return b
        }
        CATransaction.commit()
    }
    func clock(_ t: TimeInterval) -> String { let s = Int(t); return s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : "\(s / 60):\(String(format: "%02d", s % 60))" }

    // MARK: Input

    @objc func answered(_ b: AnswerButton) { broker.answer(b.requestId, b.answer) }
    @objc func releaseTop() { if let r = broker.queue.top { broker.release(r.id, why: "the user chose the terminal") } }

    /// ⌥↩ allow once, ⌥⌫ deny, ⌥↓ next, esc folds. Risky requests get no shortcut.
    func key(_ e: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        if e.keyCode == 53 { pinned = false; hovered = false; selected = 0; roomOpen = false; quickOpen = false; Feel.haptic(.tick); update(); return true }
        let items = broker.queue.waiting
        // ←/→ pick a waiting approval
        if (e.keyCode == 123 || e.keyCode == 124), items.count > 1 {
            let n = min(items.count, 4)
            selected = (selected + (e.keyCode == 124 ? 1 : n - 1)) % n
            Feel.haptic(.tick)
            refreshContent(clear: true)
            return true
        }
        guard e.modifierFlags.contains(.option) else { return false }
        guard !items.isEmpty else { return false }
        let r = items[min(selected, items.count - 1)]
        switch e.keyCode {
        case 36: if ApprovalQueue.shortcutAllowed(r) { broker.answer(r.id, .allowOnce) }; return true
        case 51: if ApprovalQueue.shortcutAllowed(r) { broker.answer(r.id, .deny) }; return true
        case 125: selected = (selected + 1) % min(items.count, 4); Feel.haptic(.tick); refreshContent(clear: true); return true
        default: return false
        }
    }

    /// Hover intent: it opens once the pointer rests for 120 ms (crossing the menu bar doesn't pop it) and folds 300 ms
    /// after the pointer leaves (a wobble at the edge doesn't snap it shut). The pointer's real position decides.
    private func hover(_ on: Bool, after delay: TimeInterval) {
        hoverWork?.cancel()
        guard hovered != on else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoverWanted(at: NSEvent.mouseLocation) == on else { return }
            self.hovered = on
            if !on { self.quickOpen = false }
            if on && self.needsKeys { self.panel.makeKey() }
            self.update()
            if on { Feel.haptic(.tick) }  // paired with the notch swelling to hover
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Click pins. Pulling the notch down past 130 pt opens the room; an upward flick dismisses a big state; holding
    /// still (or a force click) opened the quick actions. Clicks on buttons, the scrubber and the room are theirs.
    func mouseUp() {
        defer { pressStart = nil; dragStart = nil }
        holdWork?.cancel()
        guard pressStart != nil, !pressOnControl else { return }
        if overPull {
            overPull = false
            pullSpring.animate(to: 0, .pull)
            roomOpen = true
            Feel.haptic(.snap)  // with the room opening
            update()
            return
        }
        if pullSpring.value > 0.5 { pullSpring.animate(to: 0, .pull) }
        if let v = flickSpeed(), v > NotchFeel.flickSpeed, Self.big.contains(state) {
            SoundKit.shared.play(.whoosh)
            fold()
            return
        }
        guard !dragged, state != .quick, state != .knock, state != .queue else { return }
        pinned.toggle()
        Feel.haptic(.snap)
        update()
    }

    /// #7: the rubber band follows a downward drag, then resists; a tick each way across the threshold.
    func dragMoved() {
        guard let start = dragStart, !pressOnControl else { return }
        let p = NSEvent.mouseLocation
        if hypot(p.x - start.x, p.y - start.y) > 4 { dragged = true; holdWork?.cancel() }
        dragSamples.append((CACurrentMediaTime(), p.y))
        if dragSamples.count > 6 { dragSamples.removeFirst(dragSamples.count - 6) }
        guard ![.knock, .queue, .quick, .room].contains(state) else { return }
        let band = NotchFeel.band(start.y - p.y)
        pullSpring.hold(at: band)
        NotchDriver.shared.wake()
        let over = band > NotchFeel.pullThreshold
        if over != overPull { overPull = over; Feel.haptic(.tick) }  // paired with the shape crossing the line
    }

    /// Upward speed from the last few drag samples, in points per second.
    private func flickSpeed() -> CGFloat? {
        guard let a = dragSamples.first, let b = dragSamples.last, b.t > a.t else { return nil }
        return (b.y - a.y) / CGFloat(b.t - a.t)
    }

    /// #9: a force click opens the quick actions (no haptic: the trackpad clicks itself); pressure deepens the dent.
    func pressure(_ e: NSEvent) {
        if e.stage >= 2 { if !quickOpen { openQuick() } }
        else if e.stage == 1 { press.animate(to: NotchFeel.pressScale - 0.04 * Double(e.pressure), .press) }
    }

    func openQuick() {
        holdWork?.cancel()
        guard !quickOpen else { return }
        quickOpen = true
        SoundKit.shared.play(.boing)
        update()
    }

    /// Folds whatever the user opened (pin, room, quick actions); approvals stay until they're answered.
    func fold() {
        pinned = false; roomOpen = false; quickOpen = false
        update()
    }

    /// #11 ⌥⌘N: open the notch (the live run, or the room when nothing runs), or fold it.
    func toggleNotch() {
        if Self.big.contains(state) && state != .knock && state != .queue { fold() }
        else if run.started != nil { pinned = true; update() }
        else { roomOpen = true; update() }
        Feel.haptic(.tick)
    }

    /// The quick actions card.
    func quickCard() {
        let safe = broker.queue.waiting.filter { !$0.risky }
        let approve = NSButton(title: safe.isEmpty ? "Approve safe calls" : "Approve \(safe.count) safe", target: self, action: #selector(approveSafe))
        approve.isEnabled = !safe.isEmpty
        let mute = NSButton(title: "Mute 1h", target: self, action: #selector(muteHour))
        let room = NSButton(title: "Open room", target: self, action: #selector(openRoomNow))
        for b in [approve, mute, room] { b.bezelStyle = .rounded }
        stack.addArrangedSubview(row([approve, mute, room, spacer()]))
    }
    /// Answers only the ordinary requests; anything that deletes, pushes or spends still needs its own click.
    @objc func approveSafe() {
        for r in broker.queue.waiting where !r.risky { broker.answer(r.id, .allowOnce) }
        quickOpen = false
        update()
    }
    @objc func muteHour() { quickOpen = false; backend?.pause(minutes: 60); update() }
    @objc func openRoomNow() { quickOpen = false; roomOpen = true; Feel.haptic(.snap); update() }

    // MARK: Heartbeat (#21)

    /// While an approval waits: a slow double tap every 1.4 s, only with a finger on the trackpad, for 30 s at most,
    /// each one with a pulse of the rim.
    private func heartbeatTick() {
        let waiting = !broker.queue.waiting.isEmpty
        if waiting, heartbeat == nil {
            heartbeatStart = Date()
            let t = Timer.scheduledTimer(withTimeInterval: NotchFeel.heartbeatEvery, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                guard Date().timeIntervalSince(self.heartbeatStart) <= NotchFeel.heartbeatFor else { t.invalidate(); return }
                if self.fingerDown { self.shape.beat(); Feel.haptic(.heartbeat) }
            }
            t.tolerance = 0.1
            heartbeat = t
        } else if !waiting, let t = heartbeat {
            t.invalidate()
            heartbeat = nil
        }
    }

    private func interactive(at p: NSPoint) -> Bool {
        var v = panel.contentView?.hitTest(p)
        while let view = v, view !== panel.contentView {
            if view is NSButton || view is ScrubView || view is RoomView { return true }
            v = view.superview
        }
        return false
    }
}

final class AnswerButton: NSButton {
    var requestId = ""
    var answer = Answer.allowOnce
}
