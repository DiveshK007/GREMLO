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
    /// Key only when there's something to type at (an approval, the pinned ticker, the room, quick actions), so a plain
    /// click never takes the keyboard and the panel never has to blink out and back to return it.
    var allowsKey: () -> Bool = { true }
    override var canBecomeKey: Bool { allowsKey() }
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
    private var clickWork: DispatchWorkItem?
    private var placed = NSRect.zero     // the shape's target, in screen points
    private var generation = 0           // a newer transition cancels an older one's content swap
    // Notch feel: the notch is one spring-driven path in a fixed, transparent panel (NotchFeel+Mac.swift).
    let shape = NotchShapeLayer()
    let W = Spring(190), H = Spring(32), R = Spring(12)
    let lean = Spring(0, .lean), squash = Spring(0, .squash), press = Spring(1, .press), openness = Spring(0, .close)
    private var leanGrow: (w: Double, h: Double) = (0, 0)
    private var wasBig = false
    private var skipClose = false   // a flick already played its whoosh; the close spring stays quiet
    private var swapPending = false      // closing: the old content is fading out, the new waits
    var idleRow: Row?
    var idleUntil = Date.distantPast
    private var idleTimer: Timer?
    private var moveMonitors: [Any] = []
    static let big: Set<LiveState> = [.ticker, .knock, .queue, .room, .stuck, .drop, .done, .quick]
    /// A pull opens the room from these. Approvals, the quick card, a drop and the room itself don't stretch.
    static let pullable: Set<LiveState> = Set(LiveState.allCases).subtracting([.knock, .queue, .quick, .drop, .room])
    // phase B: pull, flick, force click, heartbeat
    let pullSpring = Spring(0, .pull)
    /// Extra drop of the notch while the pet is leaving or coming home. The door is this shape, not a second window.
    let mouth = Spring(0, .open)
    var quickOpen = false
    private var dragStart: NSPoint?
    private var dragged = false, overPull = false
    private var dragSamples: [(t: CFTimeInterval, y: CGFloat)] = []
    private var holdWork: DispatchWorkItem?
    private var heartbeat: Timer?
    private var heartbeatStart = Date.distantPast
    var fingerDown = false
    // phase C: Mac events, personality
    var moment: MacMoment?
    var momentUntil = Date.distantPast
    var breathUntil = Date.distantPast
    /// True while Music or Spotify is playing and the bop setting is on. The title stays in the menu bar.
    var hearingMusic = false { didSet { if hearingMusic != oldValue { syncBop() } } }

    /// Bobs the housing while music plays and the pointer is near. The ticker leaves when either stops, so the clock can pause.
    func syncBop() {
        guard hearingMusic, hovered, !Motion.reduce else { return }
        NotchDriver.shared.addTicker { [weak self] _ in
            guard let self else { return false }
            return self.hearingMusic && self.hovered && !Motion.reduce
        }
    }
    private var konami = Konami()
    private var flinging = false
    lazy var events = MacEvents(live: self)
    let typing = TypingWatch(), music = MusicWatch()
    static let leans: Set<LiveState> = [.rest, .think]
    var softRunCents: Int? { (defaults.object(forKey: "softAlertRunCents") as? Int).flatMap { $0 > 0 ? $0 : nil } }
    var softDayCents: Int? { (defaults.object(forKey: "softAlertDayCents") as? Int).flatMap { $0 > 0 ? $0 : nil } }
    /// An amber pulse when spend crosses a user-set amount. It never blocks or stops an agent.
    var softAlert: Bool {
        SoftAlert.due(costMicroCents: run.runUsage.flatMap(Prices.costMicroCents), limitCents: softRunCents)
            || SoftAlert.due(costMicroCents: run.dayMicroCents, limitCents: softDayCents)
    }

    var notchHeight: CGFloat { mainScreen.safeAreaInsets.top > 0 ? mainScreen.safeAreaInsets.top : 0 }
    /// The camera housing's width, between the menu bar's two halves; 0 without a notch.
    var hardwareNotchWidth: CGFloat {
        guard notchHeight > 0, let l = mainScreen.auxiliaryTopLeftArea, let r = mainScreen.auxiliaryTopRightArea else { return 0 }
        return mainScreen.frame.width - l.width - r.width
    }

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
        panel.allowsKey = { [weak self] in self?.needsKeys ?? false }
        Motion.reduce = reduceMotion
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            Motion.reduce = reduceMotion
        }
        NotchDriver.shared.attach(to: drop)
        NotchDriver.shared.register(W, H, R, lean, squash, press, openness, pullSpring, mouth)
        NotificationCenter.default.addObserver(forName: .gremloPetMouth, object: nil, queue: .main) { [weak self] n in
            let open = (n.userInfo?["open"] as? Bool) == true
            self?.mouth.animate(to: open ? 22 : 0, open ? .open : .close)
        }
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
            if on { self.blip(.snap, sound: .tick) } else if Date() >= self.toastUntil { self.blip() }
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
                self.clickWork?.cancel()
                self.hovered = true  // a click means the pointer is here
                self.pressStart = Date()
                self.pressOnControl = self.interactive(at: e.locationInWindow)
                // the press dent and its boop belong to a press on the notch itself; a button gives its own feedback,
                // and denting a whole card under it read as a jerk
                if !self.pressOnControl {
                    // the boop lands on the deepest frame of the dent, with the pixels
                    self.press.animate(to: NotchFeel.pressScale, .press, onPeak: { [weak self] in
                        guard self?.pressStart != nil else { return }
                        self?.blip(.boop)
                    })
                }
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
                self.mouseUp(clicks: e.clickCount)
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
        SoundKit.shared.warm()
        let clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        clock.tolerance = 0.2
        scheduleIdleLife()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = self.events
            self.applyOptIns()
        }
    }

    // MARK: State

    func inputs() -> NotchLive.Inputs {
        var i = NotchLive.Inputs()
        i.waiting = broker.queue.waiting.count
        i.doneUntil = run.doneUntil
        // A nearby cursor only swells the small notch. The live card opens when the user pins it (a click),
        // so brushing the menu bar during a run doesn't throw the big card open.
        // A click pins the card. The pointer being near only leans the housing.
        i.hoverOrPin = pinned && run.started != nil
        // A meeting is a glance from the pet, two minutes out. It does not take the housing.
        i.toolRunning = NotchLive.toolShowing(running: run.toolRunning, lastToolEnd: run.lastToolEnd, runEnded: run.endedAt != nil, now: Date())
        i.thinking = run.thinking
        i.dragging = dragging || Date() < toastUntil
        i.quick = quickOpen
        i.roomOpen = roomOpen
        i.focus = backend?.privacy.focus != nil
        i.stuck = backend?.hunt.stuckTrigger != nil
        i.meetingSoon = false
        if let g = backend?.growth { i.egg = g.isEgg && backend?.pet.path != .home || unlockNoteShowing }
        i.sleeping = backend.map { $0.pet.napping || $0.pet.night && $0.pet.path == .home } ?? false
        i.offline = backend?.pet.offline ?? false
        return i
    }

    func update() {
        // the panel can shrink out from under the pointer (an answered approval folds the card), and then no
        // mouseExited comes; without this the run-over ticker stayed up for good instead of folding to rest
        hovered = NotchLive.stillHovered(hovered, pointerInside: hoverWanted(at: NSEvent.mouseLocation) != false,
                                         exitPending: false)
        let s = NotchLive.resolve(inputs(), now: Date())
        if s != state {
            print("notch: \(state.rawValue) -> \(s.rawValue)")
            if state == .ticker { scrubLabel = nil }
            if s != .queue { selected = 0 }
            state = s
            place(animated: true)
            if state == .knock || state == .queue { panel.makeKey() }
        } else if target() != placed {
            place(animated: true)  // same state, new size: another agent joined the queue, or a note dropped below the notch
        } else {
            refreshContent()
            if target() != placed { place(animated: true) }  // new rows, new height (a risky note came or went)
        }
        // Resign the keyboard without ordering the panel out. Ordering it out and back was a visible jerk on every click.
        if panel.isKeyWindow, state != .knock, state != .queue, NSEvent.pressedMouseButtons == 0 { panel.resignKey() }
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
    var needsKeys: Bool { !broker.queue.waiting.isEmpty || pinned || roomOpen || quickOpen }

    // MARK: Layout and motion

    var unlockNoteShowing: Bool { backend?.growth.unlockNote.map { Date() < $0.until } ?? false }

    /// Tall states open below the camera housing. On a notched Mac a sentence in a short state would sit behind it, so
    /// offline and the new-egg note drop below as well.
    /// Where the shape is heading: the state's size, hover's when the pointer rests on a small notch, idle life's.
    /// A Mac event or personality moment showing right now (only over a quiet state).
    var activeMoment: MacMoment? {
        guard let m = moment, Date() < momentUntil, MacMoment.over.contains(state) else { return nil }
        return m
    }

    /// The lab's widths are for a 190 pt housing. A wider or narrower notch scales them, capped so a card can't run off the screen.
    var notchScale: Double {
        let w = Double(hardwareNotchWidth)
        return w > 40 ? min(1.2, max(0.84, w / 190)) : 1
    }
    func fit(_ s: (w: Double, h: Double)) -> (w: Double, h: Double) { (s.w * notchScale, s.h) }

    /// The camera housing. Quiet states, idle life and Mac moments all stay this wide. Height may breathe.
    var housing: (w: Double, h: Double) {
        NotchFeel.housingSize(hardware: (Double(hardwareNotchWidth), Double(notchHeight)))
    }

    var shapeSize: (w: Double, h: Double) {
        if NotchFeel.grows.contains(state) {
            let n = broker.queue.waiting.count
            var s = fit(NotchLive.size(state, agents: n))
            s.h = NotchLive.cardHeight(state, agents: n, content: cardContentH)  // approval cards fit their rows
            return s
        }
        var h = housing.h
        if state == .rest, idleRow != nil, Date() < idleUntil { h += 12 }
        if Date() < breathUntil { h += NotchFeel.breath }
        return (housing.w, h)
    }

    var belowNotch: Bool {
        NotchFeel.grows.contains(state) || notchHeight > 0 && state == .egg && unlockNoteShowing
    }

    func target() -> NSRect {
        let sz = shapeSize
        let f = mainScreen.frame
        let w = CGFloat(sz.w)
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
        contentWidth = (CGFloat(to.w) - UI.margin * 2).rounded(.down)
        shape.rimDim = s == .focus
        switch activeMoment {
        case .battery?: shape.rimColor = nsColor(hex: NotchFeel.batteryColor); shape.rimMode = .solid
        case .charging?: shape.rimColor = nsColor(hex: NotchFeel.doneColor); shape.rimMode = .solid
        default:
            shape.rimColor = nsColor(hex: s == .done ? NotchFeel.doneColor : s == .stuck ? NotchFeel.failColor : NotchFeel.agentColor(run.agent))
            shape.rimMode = s == .focus ? .solid : NotchFeel.rim(s)
        }
        let swap = { [weak self] in
            guard let self, g == self.generation else { return }
            self.refreshContent(clear: true, stagger: animated)
            let f = self.target()  // the new rows were just measured, so an approval card opens to its content
            self.placed = f
            self.spring(to: (Double(f.width), Double(f.height)), opening: opening, animated: animated)
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
        if !Self.leans.contains(state) {  // a card doesn't lean; the small notch keeps following the cursor, hover included
            leanGrow = (0, 0)
            lean.animate(to: 0, .lean)
        }
        guard animated else {
            W.hold(at: to.w); H.hold(at: to.h); R.hold(at: r); openness.hold(at: big ? 1 : 0)
            applyFrame()
            return
        }
        let p: SpringParams = opening ? .open : .close
        // a card opening gets the snap and the pop on the overshoot frame; a small hover gets a tick there too.
        // the peek coming and going with every tool only moves
        let felt = opening && to.h > 40 && state != .quick   // quick actions already clicked the trackpad; they get the boing only
        let hover = opening && !felt && hovered && Self.leans.contains(state)
        let closing = wasBig && !big
        let cue: (() -> Void)? = felt ? { [weak self] in self?.peakTap() }
            : hover ? { [weak self] in self?.hoverTap() }
            : closing && !skipClose ? { SoundKit.shared.play(.close) } : nil
        if closing { skipClose = false }
        W.animate(to: to.w + leanGrow.w, p, onPeak: cue)
        H.animate(to: to.h + leanGrow.h, p.heavier)
        R.animate(to: r, SpringParams(response: 0.4, damping: 0.9))
        openness.animate(to: big ? 1 : 0, .close)
        if !Motion.reduce { squash.kick(opening ? NotchFeel.squashOpen : NotchFeel.squashClose) }
    }

    /// #19: the snap and the pop land together, on the frame that shows the overshoot.
    private func peakTap() {
        Feel.haptic(.snap, at: .drawCompleted)
        SoundKit.shared.play(.pop)
        #if DEBUG
        print("notch: peak haptic on frame \(NotchDriver.shared.frame), width \(String(format: "%.1f", W.value)) for a target of \(String(format: "%.0f", W.target))")
        #endif
    }

    /// The small swell: a tick with the frame it arrives, not with the cursor crossing the line.
    private func hoverTap() {
        Feel.haptic(.tick, at: .drawCompleted)
        SoundKit.shared.play(.tick)
    }

    /// A touch that should be heard as well as felt. `sound` defaults to the short tick.
    private func blip(_ h: Haptic = .tick, sound: SoundKit.Sound = .tick, at time: NSHapticFeedbackManager.PerformanceTime = .now) {
        Feel.haptic(h, at: time)
        SoundKit.shared.play(sound)
    }

    /// Every display frame while something moves: the springs onto the path.
    func applyFrame() {
        guard let b = panel.contentView?.bounds, b.width > 0 else { return }
        if shape.frame != b { shape.frame = b }
        let mouthDrop = max(0, mouth.value)
        let bob = hearingMusic && hovered && !Motion.reduce ? sin(CACurrentMediaTime() * .pi * 4) * 1.6 : 0
        let g = NotchGeometry(width: W.value, height: H.value + max(0, pullSpring.value) + mouthDrop + bob, radius: R.value,
                              ear: NotchFeel.ear(width: W.value, hardwareWidth: Double(hardwareNotchWidth)), bulge: max(0, -squash.value) / 2.2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // also when called outside the frame clock (layout, a jump)
        shape.apply(g, centerX: b.midX + lean.value, top: b.maxY, squash: Motion.reduce ? 0 : squash.value, press: press.value,
                    open: openness.value, mouth: mouthDrop, showLip: !NotchFeel.grows.contains(state))
        ride(in: b, path: g.path(centerX: b.midX + lean.value, top: b.maxY))
        CATransaction.commit()
    }

    /// Rows stay put while the shape squishes. Scaling the text with the press was a jump on every click.
    /// A pull still slides them down inside the mask, with the rubber band.
    private func ride(in b: CGRect, path: CGPath) {
        guard stage.superview != nil else { return }
        if stage.frame != b { stage.frame = b }
        let drop = max(0, pullSpring.value) + max(0, mouth.value)
        stack.layer?.transform = CATransform3DMakeTranslation(lean.value, -drop * 0.85, 0)
        if stage.layer?.mask == nil { stage.layer?.mask = CAShapeLayer() }
        (stage.layer?.mask as? CAShapeLayer)?.path = path
    }

    /// The shape on screen right now (springs, not targets), so clicks land on what you see.
    var shapeOnScreen: NSRect {
        let f = mainScreen.frame
        let h = H.value + max(0, pullSpring.value) + max(0, mouth.value)
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

    /// #4: the notch leans toward a nearby cursor and swells a little. Crossing 34 pt enters hover on that
    /// frame; passing 70 pt leaves it. The 34/70 gap is the debounce, so there is no extra delay.
    func pointerMoved() {
        let p = NSEvent.mouseLocation
        passThrough()
        if Self.leans.contains(state) {
            switch hoverWanted(at: p) {
            case true?: if !hovered { setHover(true) }
            case false?: if hovered { setHover(false) }
            case nil: break
            }
        } else if hovered, hoverWanted(at: p) == false {
            hovered = false
        }
        let f = mainScreen.frame
        let l = Self.leans.contains(state) && !Motion.reduce ? NotchFeel.lean(dx: p.x - f.midX, dy: f.maxY - p.y) : NotchFeel.lean(dx: 0, dy: 1000)
        let grow = (w: Double(l.growW), h: Double(l.growH))
        guard abs(l.shift - lean.target) > 0.25 || abs(grow.w - leanGrow.w) > 0.5 else { return }  // far away: no frames
        leanGrow = grow
        lean.animate(to: l.shift, .lean)
        let sz = target()
        W.animate(to: Double(sz.width) + grow.w, .lean)
        H.animate(to: Double(sz.height) + grow.h, .lean)
    }

    /// The small hover, now. A tick lands with the swell.
    private func setHover(_ on: Bool) {
        guard hovered != on else { return }
        hovered = on
        syncBop()
        update()
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
    /// Fills the panel. Its layer scales with the notch body; the rows are laid out inside it, untransformed.
    private let stage = NSView()
    /// Live values (clock, cost, counts, bars) set in place on every refresh; views are rebuilt only when the layout changes.
    private var ticks: [() -> Void] = []
    private var contentWidth: CGFloat = 154
    /// An approval card's rows as measured, below the camera housing; nil for every other state.
    private var cardContentH: Double?
    var lastKey = ""
    var roomOpen = false
    private var swipe: CGFloat = 0
    private var scrolling = false
    private var scrollTravel: CGFloat = 0
    private var scrollSamples: [(t: CFTimeInterval, y: CGFloat)] = []

    /// What decides the layout. Everything else is a live value, so buttons are never recreated under the pointer
    /// and the pulse and the breathing edge don't restart every second.
    var layoutKey: String {
        "\(state)|\(broker.queue.waiting.map(\.id))|\(selected)|\(pinned)|\(dragging)|\(softAlert)|\(run.endedAt != nil && !run.steps.isEmpty)"
            + "|\(backend?.hunt.stuckTrigger?.line ?? "")|\(unlockNoteShowing)|\(backend?.privacy.focus != nil)|\(idleRow != nil && Date() < idleUntil)|\(activeMoment.map { "\($0)" } ?? "")"
    }

    func refreshContent(clear: Bool = false, stagger: Bool = false) {
        let key = layoutKey
        if !clear && (key == lastKey || swapPending) { ticks.forEach { $0() }; return }
        lastKey = key
        ticks = []
        stack.removeFromSuperview()
        stack = NSStackView()
        let card = NotchFeel.grows.contains(state)
        stack.orientation = .vertical
        stack.alignment = card ? .leading : .centerX
        stack.spacing = 8
        let topPad: CGFloat = card ? (notchHeight > 0 && belowNotch ? notchHeight + UI.rowY : UI.rowY) : 0
        stack.edgeInsets = NSEdgeInsets(top: topPad, left: UI.margin, bottom: card ? UI.rowY : 0, right: UI.margin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alphaValue = 1
        guard let content = panel.contentView else { return }
        if stage.superview == nil {
            stage.wantsLayer = true
            content.addSubview(stage)
        }
        stage.addSubview(stack)
        // Same centre and width as the shape, so every row shares one left and right edge.
        var pins = [stack.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
                    stack.widthAnchor.constraint(equalToConstant: contentWidth + UI.margin * 2)]
        if card {
            pins.append(stack.topAnchor.constraint(equalTo: stage.topAnchor))
        } else {
            pins.append(stack.centerYAnchor.constraint(equalTo: stage.topAnchor, constant: -CGFloat(shapeSize.h) / 2))
        }
        NSLayoutConstraint.activate(pins)
        if let m = activeMoment {
            momentContent(m)
            ticks.forEach { $0() }
            if stagger { Stagger.rows(stack.arrangedSubviews) }
            return
        }
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
            stack.addArrangedSubview(centered(eyes()))
        case .stuck: if let t = backend?.hunt.stuckTrigger { stuckCard(t) }
        case .room: if let b = backend { room(b) }
        case .focus:
            stack.addArrangedSubview(centered(eyes(asleep: true)))
        case .rest:
            if let r = idleRow, Date() < idleUntil, let frames = backend?.pet.skin.loaded.strip(r)?.frames {
                stack.addArrangedSubview(centered(SpriteView(frames: frames, size: 28)))
            }
        case .visitor: stack.addArrangedSubview(centered(eyes()))
        case .think: break  // the flowing rim says it
        case .peek: stack.addArrangedSubview(row([eyes(), spacer(), softAlert ? text("over your cost alert", 10, .amber) : pulse()]))
        case .sleep:
            let icon = dreamIcon()
            stack.addArrangedSubview(row([eyes(asleep: true), spacer(), icon]))
            ticks.append { [weak self] in self?.showDream(in: icon) }
        case .offline:
            let off = text("offline", 12, .primary)
            off.alignment = .center
            stack.addArrangedSubview(centered(off))
        case .ticker: ticker()
        case .done: stack.addArrangedSubview(centered(SpriteView(frames: frames(run.errors > 0 ? .fail : .celebrate), size: 28)))
        case .knock: if let r = broker.queue.top { knock(r) }
        case .queue: queueRows()
        }
        cardContentH = state == .knock || state == .queue ? Double(stack.fittingSize.height - (belowNotch ? notchHeight : 0)) : nil
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

    /// Two fingers on an open queue switch agents, one detent per 40 pt. A vertical drag is the same rubber
    /// band as a mouse pull: it follows, resists, and only opens the room if it is still past 130 pt when the
    /// fingers lift. Inertia after the lift is ignored, and a short flick no longer snaps the room open.
    func scrolled(_ e: NSEvent) {
        if e.momentumPhase != [] { return }
        if state == .queue, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) {
            swipe += e.scrollingDeltaX
            if abs(swipe) > NotchFeel.detent {
                let n = min(broker.queue.waiting.count, 4)
                selected = (selected + (swipe < 0 ? 1 : n - 1)) % max(n, 1)
                let dir: CGFloat = swipe < 0 ? -1 : 1
                swipe = 0
                blip()
                refreshContent(clear: true)
                slide(dir * NotchFeel.detentSlide)
            }
            if e.phase == .ended || e.phase == .cancelled { swipe = 0 }
            return
        }
        // a mouse wheel ticks with no phase; that is not a pull
        guard e.phase != [] else { return }
        if e.phase == .began || !scrolling {
            scrolling = true
            scrollTravel = 0
            overPull = false
            scrollSamples = []
        }
        // positive travel pulls the notch down (a finger moving down)
        let dy = e.isDirectionInvertedFromDevice ? e.scrollingDeltaY : -e.scrollingDeltaY
        scrollTravel += dy
        scrollSamples.append((CACurrentMediaTime(), scrollTravel))
        if scrollSamples.count > 6 { scrollSamples.removeFirst(scrollSamples.count - 6) }
        if scrollTravel > 0, Self.pullable.contains(state) {
            let band = NotchFeel.band(scrollTravel)
            pullSpring.hold(at: band)
            NotchDriver.shared.wake()
            let over = band > NotchFeel.pullThreshold
            if over != overPull { overPull = over; blip() }
        }
        if e.phase == .ended || e.phase == .cancelled {
            scrolling = false
            commitPull(band: pullSpring.value, upwardSpeed: scrollUpSpeed())
        }
    }

    /// Upward speed of this scroll, points per second. Positive is a flick up.
    private func scrollUpSpeed() -> CGFloat {
        guard let a = scrollSamples.first, let b = scrollSamples.last, b.t > a.t else { return 0 }
        return -(b.y - a.y) / CGFloat(b.t - a.t)
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
        let size = NSSize(width: contentWidth + UI.margin * 2, height: NotchLive.size(.room).h + notchHeight)
        let v = RoomView(backend: b, size: size, top: notchHeight + UI.rowY)
        v.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        v.heightAnchor.constraint(equalToConstant: size.height - notchHeight - UI.margin).isActive = true
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
        for b in [ignore, nudge, show] { b.controlSize = .small; b.setContentCompressionResistancePriority(.required, for: .horizontal) }
        stack.addArrangedSubview(row([ignore, nudge, show, spacer()]))
    }
    @objc func stuckIgnore() { backend?.hunt.ignoreRun() }
    @objc func stuckNudge() { backend?.hunt.copyNudge(); blip() }
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
        // in a row like the others, so it shares their inset and truncates inside the margin, keeping the command's
        // start and the end of its path
        let command = text(r.summary.isEmpty ? "\u{2014}" : r.summary, 12, .primary, mono: true)
        command.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(row([command]))
        var buttons: [NSView] = [button("Deny", r.id, .deny)]
        if r.canAlwaysAllow { buttons.append(button("Always allow", r.id, .alwaysAllow)) }
        buttons.append(button(r.risky ? "Allow once" : "Allow once  \u{2325}\u{21A9}", r.id, .allowOnce, primary: true))
        let terminal = NSButton(title: "Answer in terminal", target: self, action: #selector(releaseTop))
        terminal.isBordered = false
        terminal.controlSize = .small
        terminal.contentTintColor = .secondaryLabelColor
        terminal.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(row(buttons + [spacer(), terminal]))
        if r.risky { stack.addArrangedSubview(row([text("Deletes, pushes or spends: answer with a click.", 10, .secondary)])) }
    }

    func queueRows() {
        let items = Array(broker.queue.waiting.prefix(4))
        for (i, r) in items.enumerated() {
            let mark = text(i == selected ? "\u{203A}" : "", 12, .primary, mono: true)
            mark.alignment = .center
            mark.widthAnchor.constraint(equalToConstant: 12).isActive = true
            let tool = text(r.tool, 12, .primary, mono: true)
            let deny = button("Deny", r.id, .deny)
            let allow = button("Allow", r.id, .allowOnce, primary: true)
            stack.addArrangedSubview(row([mark, tool, spacer(), deny, allow]))
            if !r.summary.isEmpty {
                let summary = text(String(r.summary.prefix(80)), 11, .secondary, mono: true)
                let sub = row([summary])
                sub.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
                stack.addArrangedSubview(sub)
            }
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
        l.preferredMaxLayoutWidth = contentWidth
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }
    func row(_ v: [NSView]) -> NSStackView {
        let r = NSStackView(views: v)
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = 8
        r.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return r
    }
    /// One view, centred on the column. The two spacers take the same slack.
    func centered(_ v: NSView) -> NSStackView { row([spacer(), v, spacer()]) }
    func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
    func button(_ title: String, _ id: String, _ a: Answer, primary: Bool = false) -> NSButton {
        let b = AnswerButton(title: title, target: self, action: #selector(answered(_:)))
        b.requestId = id
        b.answer = a
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        b.setContentHuggingPriority(.required, for: .horizontal)
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
            b.frame = CGRect(x: CGFloat(i) * (w / 48), y: (14 - h) / 2, width: max(2, w / 48 - 2), height: h)
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
        if konami.feed(e.keyCode) { disco() }  // #26, while the notch has the keyboard
        if e.keyCode == 53 { pinned = false; hovered = false; selected = 0; roomOpen = false; quickOpen = false; blip(); update(); return true }
        let items = broker.queue.waiting
        // ←/→ pick a waiting approval
        if (e.keyCode == 123 || e.keyCode == 124), items.count > 1 {
            let n = min(items.count, 4)
            selected = (selected + (e.keyCode == 124 ? 1 : n - 1)) % n
            blip()
            refreshContent(clear: true)
            return true
        }
        guard e.modifierFlags.contains(.option) else { return false }
        guard !items.isEmpty else { return false }
        let r = items[min(selected, items.count - 1)]
        switch e.keyCode {
        case 36: if ApprovalQueue.shortcutAllowed(r) { broker.answer(r.id, .allowOnce) }; return true
        case 51: if ApprovalQueue.shortcutAllowed(r) { broker.answer(r.id, .deny) }; return true
        case 125: selected = (selected + 1) % min(items.count, 4); blip(); refreshContent(clear: true); return true
        default: return false
        }
    }

    /// Click opens or folds. The toggle waits a beat so a triple-click is one trick, not an open and a close
    /// and then a trick. Pulling past 130 pt opens the room; an upward flick dismisses a big state.
    func mouseUp(clicks: Int = 1) {
        defer { pressStart = nil; dragStart = nil }
        holdWork?.cancel()
        if flinging {  // #10: the pet was dragged out of the room; let it fly
            flinging = false
            backend?.pet.release(at: NSEvent.mouseLocation)
            return
        }
        guard pressStart != nil, !pressOnControl else { return }
        if dragged || overPull || pullSpring.value > 0.5 {
            commitPull(band: pullSpring.value, upwardSpeed: flickSpeed() ?? 0)
            return
        }
        guard state != .quick, state != .knock, state != .queue else { return }
        noteClick(clicks)
    }

    /// Releasing commits, in one spring. The third click is a trick.
    private func noteClick(_ clicks: Int) {
        clickWork?.cancel()
        if clicks >= 3 { trick(); return }
        guard clicks == 1 else { return }
        toggleFromClick()
    }

    /// A click on a running agent pins the live card. With nothing running it opens the room. A click on a card
    /// the user opened folds it. Approvals are not in here: they stay until they're answered.
    private func toggleFromClick() {
        if Self.big.contains(state), state != .knock, state != .queue {
            fold()
            return
        }
        if run.started != nil {
            pinned = true
        } else {
            roomOpen = true
        }
        update()   // the snap and the pop come from the opening spring's peak
    }

    /// Finger up on a pull. The room opens only past the threshold; anything shorter springs back.
    private func commitPull(band: CGFloat, upwardSpeed: CGFloat) {
        let end = NotchFeel.pullEnd(band: band, upwardSpeed: upwardSpeed, big: Self.big.contains(state), roomOpen: roomOpen)
        overPull = false
        scrollTravel = 0
        scrollSamples = []
        switch end {
        case .openRoom:
            pullSpring.animate(to: 0, .pull)
            roomOpen = true
            update()   // snap and pop land on the peak, not on the finger lifting
        case .dismiss:
            pullSpring.animate(to: 0, .pull)
            skipClose = true
            SoundKit.shared.play(.whoosh)
            fold()
        case .release:
            if pullSpring.value > 0.5 { pullSpring.animate(to: 0, .pull) }
        }
    }

    /// #7: the rubber band follows a downward drag, then resists; a tick each way across the threshold.
    func dragMoved() {
        guard let start = dragStart, !pressOnControl else { return }
        let p = NSEvent.mouseLocation
        if hypot(p.x - start.x, p.y - start.y) > 4 { dragged = true; holdWork?.cancel() }
        dragSamples.append((CACurrentMediaTime(), p.y))
        if dragSamples.count > 6 { dragSamples.removeFirst(dragSamples.count - 6) }
        // #10: dragging out of the room takes the pet with you; it flies when you let go
        if flinging { backend?.pet.drag(to: p); return }
        if state == .room, let pet = backend?.pet, pet.path == .home, !placed.contains(p) {
            flinging = true
            roomOpen = false
            pet.grabFromNotch(at: p)
            update()
            return
        }
        guard Self.pullable.contains(state) else { return }
        let band = NotchFeel.band(start.y - p.y)
        pullSpring.hold(at: band)
        NotchDriver.shared.wake()
        let over = band > NotchFeel.pullThreshold
        if over != overPull { overPull = over; blip() }  // paired with the shape crossing the line
    }

    /// Upward speed from the last few drag samples, in points per second.
    private func flickSpeed() -> CGFloat? {
        guard let a = dragSamples.first, let b = dragSamples.last, b.t > a.t else { return nil }
        return (b.y - a.y) / CGFloat(b.t - a.t)
    }

    /// #9: a force click opens the quick actions (no haptic: the trackpad clicks itself); pressure deepens the dent.
    func pressure(_ e: NSEvent) {
        if e.stage >= 2 { if !quickOpen { openQuick() } }
        else if e.stage == 1, !pressOnControl { press.animate(to: NotchFeel.pressScale - 0.04 * Double(e.pressure), .press) }
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
        if Self.big.contains(state) && state != .knock && state != .queue { blip(); fold() }
        else if run.started != nil { pinned = true; update() }
        else { roomOpen = true; update() }
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
    @objc func openRoomNow() { quickOpen = false; roomOpen = true; update() }

    // MARK: Moments (#24-27)

    /// A moment lives inside the housing: a face, a rim colour, and one breath of the edge. It does not resize the notch.
    func show(_ m: MacMoment) {
        let same = activeMoment == m
        moment = m
        momentUntil = Date().addingTimeInterval(m.hold)
        breathUntil = Date().addingTimeInterval(0.45)
        if !same { update() }
        DispatchQueue.main.asyncAfter(deadline: .now() + m.hold + 0.05) { [weak self] in self?.update() }
    }

    /// The Mac is changing its own volume. Ears perk. The system overlay is the volume UI.
    func perk() {
        breathUntil = Date().addingTimeInterval(0.45)
        backend?.pet.perk()
        update()
    }

    func batteryLow(_ percent: Int) {
        show(.battery(percent))
        burst(.sweat)
        Feel.haptic(.knock)  // with the amber rim and the sweat
        SoundKit.shared.play(.fail)
    }
    func pluggedIn() {
        show(.charging)
        SoundKit.shared.play(.chomp)
        Feel.haptic(.boop)   // with the pet eating the bolt
    }
    func screenshot() {
        show(.screenshot)
        SoundKit.shared.play(.shutter)
    }
    /// #26 triple click: a random trick for 2.4 s.
    func trick() {
        show(.trick([Row.backflip, .juggle, .moonwalk].randomElement()!))
        Feel.haptic(.snap)
        SoundKit.shared.play(.boing)
    }
    /// #26 the Konami code: a disco rim, a moonwalk and confetti.
    func disco() {
        show(.trick(.moonwalk))
        if !Motion.reduce { shape.disco() }
        burst(.confetti)
        SoundKit.shared.play(.chime)
    }
    func applyOptIns() {
        typing.set(defaults.bool(forKey: "typingPace"), live: self)
        music.set(defaults.bool(forKey: "musicBop"), live: self)
    }

    func frames(_ r: Row) -> [CGImage] { backend?.pet.skin.loaded.strip(r)?.frames ?? [] }

    func momentContent(_ m: MacMoment) {
        let rowName: Row
        switch m {
        case .volume: rowName = .walk
        case .battery: rowName = .fail
        case .charging, .home: rowName = .gulp
        case .screenshot: rowName = .greet
        case .trick(let r): rowName = r
        case .typing: rowName = .celebrate
        case .nap: rowName = .night
        case .music: return
        }
        stack.addArrangedSubview(centered(SpriteView(frames: frames(rowName), size: 28)))
    }

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
