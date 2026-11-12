import AppKit
import NotchiCore

// Notch Live on the Mac (spec D §5, R2 §9, R3 §2). Rules are in NotchiCore/NotchLive.swift; this draws them and
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
}

/// What the current run is doing, for the ticker and the done card. Counts and times only; nothing leaves the Mac.
final class RunTracker {
    var thinking = false, toolRunning = false
    var started: Date?, endedAt: Date?, doneUntil: Date?
    var tools = 0, errors = 0, approvalsAtStart = 0
    var lastTool = ""
    var agent = "Claude Code"
    var activity: [Character] = []   // r read, e edit, x run, f failed, a approval, p passed
    var reader = TranscriptUsageReader()
    /// Estimated spend today across runs (micro-cents), for the per-day soft alert. Local only.
    var dayMicroCents = 0
    private var day = Calendar.current.startOfDay(for: Date())
    private var transcript: String?
    private var offset: UInt64 = 0

    func event(_ hook: [String: Any], approvalsAnswered: Int) {
        let ev = hook["hook_event_name"] as? String ?? ""
        let tool = hook["tool_name"] as? String
        if let path = hook["transcript_path"] as? String, path != transcript { transcript = path; offset = 0; reader = TranscriptUsageReader() }
        switch ev {
        case "UserPromptSubmit":
            started = Date(); endedAt = nil; doneUntil = nil; tools = 0; errors = 0; activity = []
            thinking = true; approvalsAtStart = approvalsAnswered
        case "PreToolUse":
            thinking = false; toolRunning = true; tools += 1; lastTool = tool ?? ""
            mark(Tools.prop(tool: tool ?? "", command: (hook["tool_input"] as? [String: Any])?["command"] as? String))
        case "PostToolUse":
            toolRunning = false
        case "PermissionRequest": push("a")
        case "Stop", "StopFailure":
            thinking = false; toolRunning = false; endedAt = Date()
            if ev == "StopFailure" { errors += 1; push("f") } else { push("p") }
            doneUntil = Date().addingTimeInterval(NotchLive.doneHold)
        default: break
        }
        tail()
    }

    private func mark(_ p: Prop?) {
        switch p {
        case .magnifier, .globe: push("r")
        case .wrench, .notepad: push("e")
        default: push("x")
        }
    }
    private func push(_ c: Character) { activity.append(c); if activity.count > 48 { activity.removeFirst(activity.count - 48) } }

    /// Reads only the new bytes of the transcript since last time.
    func tail() {
        guard let path = transcript, let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < offset { offset = 0; reader = TranscriptUsageReader() }
        try? h.seek(toOffset: offset)
        let data = (try? h.readToEnd()) ?? Data()
        offset += UInt64(data.count)
        let before = Prices.costMicroCents(reader.usage) ?? 0
        reader.feed(String(decoding: data, as: UTF8.self))
        let today = Calendar.current.startOfDay(for: Date())
        if today != day { day = today; dayMicroCents = 0 }
        dayMicroCents += max(0, (Prices.costMicroCents(reader.usage) ?? 0) - before)
    }

    var elapsed: TimeInterval { started.map { (endedAt ?? Date()).timeIntervalSince($0) } ?? 0 }
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
    private var pressStart: Date?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    var softRunCents: Int? { (defaults.object(forKey: "softAlertRunCents") as? Int).flatMap { $0 > 0 ? $0 : nil } }
    var softDayCents: Int? { (defaults.object(forKey: "softAlertDayCents") as? Int).flatMap { $0 > 0 ? $0 : nil } }
    /// An amber pulse when spend crosses a user-set amount. It never blocks or stops an agent.
    var softAlert: Bool {
        SoftAlert.due(costMicroCents: Prices.costMicroCents(run.reader.usage), limitCents: softRunCents)
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
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSView()
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.black.cgColor  // always black, whatever the theme
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom corners: the hardware curve
        let track = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        panel.contentView?.addTrackingArea(track)
        broker.onChange = { [weak self] in self?.update() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) == true ? nil : e }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            if e.type == .leftMouseDown { self.pressStart = Date() } else { self.mouseUp() }
            return e
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
        i.toolRunning = run.toolRunning
        i.thinking = run.thinking
        i.sleeping = backend.map { $0.pet.napping || $0.pet.night && $0.pet.path == .home } ?? false
        i.offline = backend?.pet.offline ?? false
        return i
    }

    func update() {
        let s = NotchLive.resolve(inputs(), now: Date())
        if s != state { print("notch: \(state.rawValue) -> \(s.rawValue)"); state = s; place(animated: true) } else { refreshContent() }
        if s == .knock || s == .queue { panel.makeKey() }
    }

    // MARK: Layout and motion

    func place(animated: Bool) {
        let sz = NotchLive.size(state, agents: broker.queue.waiting.count)
        let f = mainScreen.frame
        let rest = state == .rest && notchHeight > 0
        let w = rest ? max(CGFloat(sz.w), (mainScreen.auxiliaryTopRightArea.map { f.width - $0.width - (mainScreen.auxiliaryTopLeftArea?.width ?? 0) }) ?? CGFloat(sz.w)) : CGFloat(sz.w)
        let h = CGFloat(sz.h) + (CGFloat(sz.h) > 40 ? notchHeight : 0)
        let frame = NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
        refreshContent(clear: true)
        guard animated else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { c in
            // bloom: 420 ms, cubic-bezier(.34, 1.4, .5, 1); Reduce Motion: a 120 ms fade instead
            c.duration = reduceMotion ? 0.12 : 0.42
            c.timingFunction = reduceMotion ? CAMediaTimingFunction(name: .linear) : CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.5, 1)
            panel.animator().setFrame(frame, display: true)
        }
        if state == .knock && !reduceMotion { shake() }
        if state == .done && !reduceMotion { confetti() }
        if state == .done { Feel.haptic(.tick) }
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
    private var lastKey = ""

    func refreshContent(clear: Bool = false) {
        let key = "\(state)|\(broker.queue.waiting.map(\.id))|\(selected)|\(run.tools)|\(Int(run.elapsed))|\(run.reader.usage.total)|\(pinned)"
        if !clear && key == lastKey { return }
        lastKey = key
        stack.removeFromSuperview()
        stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: notchHeight > 0 && NotchLive.size(state).h > 40 ? notchHeight + 6 : 8, left: 18, bottom: 10, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = panel.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: content.topAnchor)])
        border(state == .think ? breathing() : nil)
        switch state {
        case .rest, .room, .egg, .visitor, .focus: break
        case .think: break  // the breathing accent edge says it
        case .peek: stack.addArrangedSubview(row([eyes(), spacer(), softAlert ? text("over your cost alert", 10, .amber) : pulse()]))
        case .sleep: stack.addArrangedSubview(row([eyes(asleep: true), spacer(), text("Zzz", 11, .secondary)]))
        case .offline: stack.addArrangedSubview(text("Can't reach the network \u{00B7} sleeping safely", 12, .primary))
        case .ticker: ticker()
        case .done: done()
        case .knock: if let r = broker.queue.top { knock(r) }
        case .queue: queueRows()
        }
    }

    func ticker() {
        let cost = run.reader.usage.total > 0 ? Prices.label(run.reader.usage) : "\u{2014}"
        let alert = softAlert
        stack.addArrangedSubview(row([text(run.lastTool.isEmpty ? "waiting" : run.lastTool, 13, .primary, mono: true), spacer(),
                                      text(run.agent, 11, .secondary)]))
        stack.addArrangedSubview(row([text("\(run.tools) tools \u{00B7} \(clock(run.elapsed))", 11, .secondary), spacer(),
                                      text(cost, 11, alert ? .amber : .secondary, mono: true)]))
        stack.addArrangedSubview(bars())
    }

    func done() {
        let answered = broker.approvalsAnswered - run.approvalsAtStart
        let cost = run.reader.usage.total > 0 ? Prices.label(run.reader.usage) : "\u{2014}"
        stack.addArrangedSubview(row([text("Done in \(clock(run.elapsed))", 15, .primary), spacer(), text(cost, 11, .secondary, mono: true)]))
        stack.addArrangedSubview(text("\(run.tools) tools \u{00B7} \(answered) approvals \u{00B7} \(run.errors) errors \u{00B7} earned \u{2014}", 11, .secondary))
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
    func text(_ s: String, _ size: CGFloat, _ tone: Tone, mono: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = mono ? .monospacedSystemFont(ofSize: size, weight: .medium) : .systemFont(ofSize: size, weight: size >= 13 ? .semibold : .regular)
        l.textColor = tone == .primary ? NSColor(white: 1, alpha: 0.85) : tone == .amber ? .systemOrange : NSColor(white: 1, alpha: 0.55)
        l.lineBreakMode = .byTruncatingTail
        return l
    }
    func row(_ v: [NSView]) -> NSStackView {
        let r = NSStackView(views: v)
        r.orientation = .horizontal
        r.spacing = 8
        r.widthAnchor.constraint(equalToConstant: panel.frame.width > 100 ? max(panel.frame.width, CGFloat(NotchLive.size(state).w)) - 36 : CGFloat(NotchLive.size(state).w) - 36).isActive = true
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
        let w: CGFloat = CGFloat(NotchLive.size(.ticker).w) - 36
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        v.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let accent = backend?.pet.skin.accent ?? NSColor.white.cgColor
        for (i, c) in run.activity.suffix(48).enumerated() {
            let b = CALayer()
            let h: CGFloat = c == "x" ? 12 : c == "e" ? 9 : c == "r" ? 6 : 14
            b.backgroundColor = c == "f" ? NSColor.systemRed.cgColor : c == "a" ? NSColor.white.cgColor : accent.copy(alpha: c == "p" ? 1 : 0.7)
            b.frame = CGRect(x: CGFloat(i) * (w / 48), y: 0, width: max(2, w / 48 - 2), height: h)
            v.layer?.addSublayer(b)
        }
        return v
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
        if e.keyCode == 53 { pinned = false; hovered = false; selected = 0; update(); return true }
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

    @objc func mouseEntered(with e: NSEvent) { hovered = true; Feel.haptic(.tick); panel.makeKey(); update() }
    @objc func mouseExited(with e: NSEvent) { hovered = false; update() }

    /// Click pins; a long press (over 0.6 s) pauses everything for 30 minutes.
    func mouseUp() {
        defer { pressStart = nil }
        guard let p = pressStart else { return }
        if Date().timeIntervalSince(p) > 0.6 { backend?.pause(minutes: 30); return }
        guard state != .knock && state != .queue else { return }
        pinned.toggle()
        Feel.haptic(.snap)
        update()
    }
}

final class AnswerButton: NSButton {
    var requestId = ""
    var answer = Answer.allowOnce
}
