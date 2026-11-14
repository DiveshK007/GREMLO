import AppKit
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
    private var placed = NSRect.zero     // the frame the panel is moving to
    private var generation = 0           // a newer transition cancels an older one's fade-in
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
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.black.cgColor  // always black, whatever the theme
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom corners: the hardware curve
        let track = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        panel.contentView?.addTrackingArea(track)
        broker.onChange = { [weak self] in self?.update() }
        drop.onDragging = { [weak self] on in self?.dragging = on; self?.update() }
        drop.onScroll = { [weak self] e in self?.scrolled(e) }
        drop.onDropped = { [weak self] in self?.toastUntil = Date().addingTimeInterval(2); Feel.haptic(.tick); self?.update() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) == true ? nil : e }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            if e.type == .leftMouseDown {
                self.hoverWork?.cancel()
                self.hovered = true  // a click means the pointer is here, even inside the hover delay
                self.pressStart = Date()
                self.pressOnControl = self.interactive(at: e.locationInWindow)
            } else { self.mouseUp() }
            return e
        }
        // a display plugged in or a resolution change moves the notch
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.place(animated: false)
        }
        place(animated: false)
        panel.orderFrontRegardless()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
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
        hovered = NotchLive.stillHovered(hovered, pointerInside: placed.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation),
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
    var belowNotch: Bool {
        NotchLive.size(state, agents: broker.queue.waiting.count).h > 40
            || notchHeight > 0 && (state == .offline || state == .egg && unlockNoteShowing)
    }

    func target() -> NSRect {
        let sz = NotchLive.size(state, agents: broker.queue.waiting.count)
        let f = mainScreen.frame
        let rest = state == .rest && notchHeight > 0
        let w = rest ? max(CGFloat(sz.w), (mainScreen.auxiliaryTopRightArea.map { f.width - $0.width - (mainScreen.auxiliaryTopLeftArea?.width ?? 0) }) ?? CGFloat(sz.w)) : CGFloat(sz.w)
        let h = CGFloat(sz.h) + (belowNotch ? notchHeight : 0)
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h).integral
    }

    /// Old content goes at once, the shape blooms to its new size, then the new content fades in (spec R3 §2).
    func place(animated: Bool) {
        generation += 1
        let g = generation, frame = target(), s = state
        placed = frame
        contentWidth = CGFloat(NotchLive.size(s, agents: broker.queue.waiting.count).w) - 36
        panel.hasShadow = false  // a shadow recomputed every frame stutters; it comes back once the shape settles
        border(nil)
        settled = false
        refreshContent(clear: true)
        if s == .done { Feel.haptic(.tick) }
        let settle = { [weak self] in
            guard let self, g == self.generation else { return }
            self.settled = true
            self.panel.hasShadow = frame.height > 40  // one shadow, on the open surface only
            self.panel.invalidateShadow()
            self.border(s == .think ? self.breathing() : nil)
            NSAnimationContext.runAnimationGroup { c in
                c.duration = reduceMotion ? 0.12 : 0.22
                self.stack.animator().alphaValue = 1
            }
            if !reduceMotion && s == .knock { self.shake() }
            if !reduceMotion && s == .done { self.confetti() }
        }
        guard animated, !reduceMotion, panel.frame != frame else { panel.setFrame(frame, display: true); settle(); return }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.42  // bloom: cubic-bezier(.34, 1.4, .5, 1); Reduce Motion skips the resize and only fades
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.5, 1)
            self.panel.animator().setFrame(frame, display: true)
        }, completionHandler: settle)
    }

    func shake() {
        guard let layer = panel.contentView?.layer else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -8, 8, -6, 6, -3, 3, 0]
        a.duration = 0.55
        layer.add(a, forKey: "knock")
    }

    func confetti() {
        guard let layer = panel.contentView?.layer, let accent = backend?.pet.skin.accent else { return }
        let colors = [accent, NSColor.white.cgColor, accent.copy(alpha: 0.6) ?? accent]
        for i in 0..<46 {
            let bit = CALayer()
            bit.backgroundColor = colors[i % colors.count]
            bit.frame = CGRect(x: CGFloat.random(in: 0...layer.bounds.width), y: layer.bounds.height, width: 4, height: 4)
            layer.addSublayer(bit)
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.toValue = -10
            fall.duration = Double.random(in: 0.8...1.6)
            fall.beginTime = CACurrentMediaTime() + Double(i) * 0.012
            fall.isRemovedOnCompletion = false
            fall.fillMode = .forwards
            bit.add(fall, forKey: "fall")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { bit.removeFromSuperlayer() }
        }
    }

    // MARK: Content

    private var stack = NSStackView()
    /// Live values (clock, cost, counts, bars) set in place on every refresh; views are rebuilt only when the layout changes.
    private var ticks: [() -> Void] = []
    private var settled = true
    private var contentWidth: CGFloat = 154
    var lastKey = ""
    var roomOpen = false
    private var pull: CGFloat = 0
    private var swipe: CGFloat = 0

    /// What decides the layout. Everything else is a live value, so buttons are never recreated under the pointer
    /// and the pulse and the breathing edge don't restart every second.
    var layoutKey: String {
        "\(state)|\(broker.queue.waiting.map(\.id))|\(selected)|\(pinned)|\(dragging)|\(softAlert)|\(run.endedAt != nil && !run.steps.isEmpty)"
            + "|\(backend?.hunt.stuckTrigger?.line ?? "")|\(unlockNoteShowing)|\(backend?.privacy.focus != nil)"
    }

    func refreshContent(clear: Bool = false) {
        let key = layoutKey
        if !clear && key == lastKey { ticks.forEach { $0() }; return }
        lastKey = key
        ticks = []
        stack.removeFromSuperview()
        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: notchHeight > 0 && belowNotch ? notchHeight + 6 : 8, left: 18, bottom: 10, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alphaValue = settled ? 1 : 0
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
        case .drop: stack.addArrangedSubview(text(dragging ? "Drop to copy it for your agent" : "Ready to paste", 13, .primary))
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
        case .rest, .visitor: break
        case .think: break  // the breathing accent edge says it
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
    }

    func ticker() {
        let tool = text("", 13, .primary, mono: true), line = text("", 11, .secondary), cost = text("", 11, .secondary, mono: true)
        stack.addArrangedSubview(row([tool, spacer(), text(run.agent, 11, .secondary)]))
        stack.addArrangedSubview(row([line, spacer(), cost]))
        ticks.append { [weak self] in
            guard let self else { return }
            tool.stringValue = self.run.lastTool.isEmpty ? "waiting" : self.run.lastTool
            line.stringValue = self.scrubLabel ?? "\(self.run.tools) tools \u{00B7} \(self.clock(self.run.elapsed))"
            cost.stringValue = Prices.label(self.run.runUsage)
            cost.textColor = self.color(self.softAlert ? .amber : .secondary)
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
            let b = bars()
            stack.addArrangedSubview(b)
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
                swipe = 0
                Feel.haptic(.tick)
                refreshContent(clear: true)
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
        let cost = text("", 11, .secondary, mono: true)
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
    func eyes(asleep: Bool = false) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        let loaded = backend?.pet.skin.loaded
        v.layer?.contents = asleep ? loaded?.frames[.idle]?[min(5, (loaded?.frames[.idle]?.count ?? 1) - 1)] : loaded?.frames[.peek]?.first
        v.layer?.contentsGravity = .resizeAspect
        v.layer?.magnificationFilter = .nearest
        v.widthAnchor.constraint(equalToConstant: 26).isActive = true
        v.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return v
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
    func bars() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        v.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return v
    }
    func drawBars(in v: NSView) {
        let w = contentWidth
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
    func border(_ anim: CAAnimation?) {
        guard let l = panel.contentView?.layer else { return }
        l.borderWidth = anim == nil ? 0 : 1.5
        l.borderColor = backend?.pet.skin.accent
        l.removeAnimation(forKey: "breathe")
        if let anim { l.add(anim, forKey: "breathe") }
    }
    func breathing() -> CAAnimation? {
        guard !reduceMotion else { return nil }
        let a = CABasicAnimation(keyPath: "borderColor")
        a.fromValue = backend?.pet.skin.accent
        a.toValue = backend?.pet.skin.accent.copy(alpha: 0.15)
        a.duration = 0.8
        a.autoreverses = true
        a.repeatCount = .infinity
        return a
    }
    func clock(_ t: TimeInterval) -> String { let s = Int(t); return s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : "\(s / 60):\(String(format: "%02d", s % 60))" }

    // MARK: Input

    @objc func answered(_ b: AnswerButton) { broker.answer(b.requestId, b.answer) }
    @objc func releaseTop() { if let r = broker.queue.top { broker.release(r.id, why: "the user chose the terminal") } }

    /// ⌥↩ allow once, ⌥⌫ deny, ⌥↓ next, esc folds. Risky requests get no shortcut.
    func key(_ e: NSEvent) -> Bool {
        guard panel.isKeyWindow else { return false }
        if e.keyCode == 53 { pinned = false; hovered = false; selected = 0; roomOpen = false; update(); return true }
        guard e.modifierFlags.contains(.option) else { return false }
        let items = broker.queue.waiting
        guard !items.isEmpty else { return false }
        let r = items[min(selected, items.count - 1)]
        switch e.keyCode {
        case 36: if ApprovalQueue.shortcutAllowed(r) { broker.answer(r.id, .allowOnce) }; return true
        case 51: if ApprovalQueue.shortcutAllowed(r) { broker.answer(r.id, .deny) }; return true
        case 125: selected = (selected + 1) % min(items.count, 4); refreshContent(clear: true); return true
        default: return false
        }
    }

    @objc func mouseEntered(with e: NSEvent) { hover(true, after: 0.12) }
    @objc func mouseExited(with e: NSEvent) { hover(false, after: 0.3) }

    /// Hover intent: it opens once the pointer rests for 120 ms (crossing the menu bar doesn't pop it) and folds 300 ms
    /// after the pointer leaves (a wobble at the edge doesn't snap it shut). The pointer's real position decides, so the
    /// enter and exit events a resize or a keyboard hand-back produce can't flap it.
    private func hover(_ on: Bool, after delay: TimeInterval) {
        hoverWork?.cancel()
        guard hovered != on else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.panel.frame.contains(NSEvent.mouseLocation) == on else { return }
            self.hovered = on
            let before = self.state
            if on && self.needsKeys { self.panel.makeKey() }
            self.update()
            if on && self.state != before { Feel.haptic(.tick) }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Click pins; a long press (over 0.6 s) pauses everything for 30 minutes. Clicks on buttons, the scrubber and the
    /// room belong to them and do neither.
    func mouseUp() {
        defer { pressStart = nil }
        guard let p = pressStart, !pressOnControl else { return }
        if Date().timeIntervalSince(p) > 0.6 { backend?.pause(minutes: 30); return }
        guard state != .knock && state != .queue else { return }
        pinned.toggle()
        Feel.haptic(.snap)
        update()
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
