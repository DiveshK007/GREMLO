import AppKit
import GremloCore

// Settings: its own window with a sidebar, instead of one long column inside the menu bar panel. Each section is
// built fresh when shown, from the same settings the app already stores.

enum SettingsPage: String, CaseIterable {
    case general = "General", pet = "Pet", earning = "Earning", notch = "Notch and sound"
    case privacy = "Privacy", team = "Team and park", devices = "Phone and Mac", developer = "Developer"

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .pet: return "pawprint"
        case .earning: return "sparkles"
        case .notch: return "speaker.wave.2"
        case .privacy: return "hand.raised"
        case .team: return "person.2"
        case .devices: return "iphone"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        }
    }
    var blurb: String {
        switch self {
        case .general: return "How the pet lives on your screen and talks to your agent."
        case .pet: return "Pick who lives in your notch. Locked species unlock as you use it."
        case .earning: return "The one sponsored line the pet holds while your agent works."
        case .notch: return "Sounds, haptics and the little extras."
        case .privacy: return "What stays on this Mac, what leaves it, and how to pause everything."
        case .team: return "Visits from teammates' companions and the public pet park. Off unless you turn them on."
        case .devices: return "Answer approvals from your phone or Watch, and sign views with this Mac."
        case .developer: return "Test runners, git moods, the demo and the technical details."
        }
    }
}

final class SettingsWindow: NSWindow {
    static let pageWidth: CGFloat = 500
    private let nav = UI.vstack([], spacing: 2)
    private let scroll = NSScrollView()
    private(set) var page = SettingsPage.general
    var build: ((SettingsPage) -> [NSView])?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "\(productName) Settings"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        backgroundColor = UI.bg
        minSize = NSSize(width: 780, height: 420)

        let side = Box(fill: UI.surface)
        side.translatesAutoresizingMaskIntoConstraints = false
        let dot = UI.fixed(Box(fill: UI.accent, radius: 4.5), w: 9, h: 9)
        let logo = UI.hstack([dot, UI.label(productName, UI.display(22), UI.fg, wrap: false)], spacing: 8)
        let sideStack = UI.vstack([logo, nav], spacing: 22, insets: NSEdgeInsets(top: 52, left: 14, bottom: 16, right: 14))
        sideStack.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(sideStack)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(side)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            side.topAnchor.constraint(equalTo: root.topAnchor), side.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            side.leadingAnchor.constraint(equalTo: root.leadingAnchor), side.widthAnchor.constraint(equalToConstant: 212),
            sideStack.topAnchor.constraint(equalTo: side.topAnchor), sideStack.leadingAnchor.constraint(equalTo: side.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: side.trailingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        contentView = root
    }

    func show(_ p: SettingsPage? = nil) {
        if let p { page = p }
        reload()
        if !isVisible { center() }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    @objc func go(_ b: NSButton) {
        page = SettingsPage.allCases[b.tag]
        reload()
        scroll.contentView.scroll(to: .zero)
    }

    /// Rebuilds the sidebar and the current section. Cheap: a section is a few dozen views.
    func reload() {
        nav.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, p) in SettingsPage.allCases.enumerated() {
            let on = p == page
            let b = Btn(p.rawValue, style: on ? .secondary : .ghost, symbol: p.symbol, target: self, action: #selector(go(_:)))
            b.tag = i
            b.alignment = .left
            b.tint = on ? UI.accentText : nil
            b.setAccessibilityValue(on)
            UI.fixed(b, w: 184, h: 30)
            nav.addArrangedSubview(b)
        }
        let head = UI.vstack([UI.label(page.rawValue, UI.display(34), UI.fg, wrap: false),
                              UI.label(page.blurb, UI.body(13), UI.text2, width: SettingsWindow.pageWidth)], spacing: 6)
        let body = UI.vstack([head] + (build?(page) ?? []), spacing: 26, insets: NSEdgeInsets(top: 48, left: 34, bottom: 40, right: 34))
        let doc = FlippedClip.wrap(body)
        body.layoutSubtreeIfNeeded()
        doc.frame = NSRect(origin: .zero, size: body.fittingSize)
        scroll.documentView = doc
    }
}

extension Backend {
    var pageWidth: CGFloat { SettingsWindow.pageWidth }

    func settingsPage(_ p: SettingsPage) -> [NSView] {
        switch p {
        case .general: return generalGroups()
        case .pet: return petGroups()
        case .earning: return earningGroups()
        case .notch: return feelControls() + [extrasGroup()]
        case .privacy: return privacyControls()
        case .team: return socialControls()
        case .devices: return phoneControls() + [thisMacGroup(), purseGroup()]
        case .developer: return huntControls() + [demoGroup()] + advancedControls()
        }
    }

    // MARK: General

    func generalGroups() -> [NSView] {
        let w = pageWidth
        let connected = ClaudeHooks.isConnected
        let hooks = Btn(connected ? "Disconnect" : "Connect", style: connected ? .secondary : .primary, target: self, action: #selector(toggleClaudeHooks))
        let claude = UI.group("Claude Code", [
            UI.row(connected ? "Connected" : "Not connected",
                   connected ? "The pet reacts to every session. Your other hooks are kept." : "One click adds the hooks to ~/.claude/settings.json, with a backup first.", hooks, width: w),
        ], width: w)

        let slider = NSSlider(value: walkSpeed, minValue: 0.5, maxValue: 2, target: self, action: #selector(setWalkSpeed(_:)))
        slider.trackFillColor = UI.accent
        UI.fixed(slider, w: 150)
        let screen = UI.group("On your screen", [
            UI.row("Theme", nil, themeControl(), width: w),
            UI.row("Show over full-screen apps", nil, Toggle(on: allDesktops, target: self, action: #selector(toggleAllDesktops(_:)), label: "Show over full-screen apps"), width: w),
            UI.row("Walk speed", nil, slider, width: w),
            UI.row("Go home after", "How long it stays out once the agent is done.",
                   Seg(["30s", "75s", "180s"], selected: [30.0, 75, 180].firstIndex(of: homeAfter) ?? -1, target: self, action: #selector(setHomeAfter(_:))), width: w),
            UI.row("Remind me", "A nudge when the agent is done and you haven't looked.",
                   Seg(["Off", "2 min", "5 min", "10 min"], selected: [0.0, 2, 5, 10].firstIndex(of: reminderMinutes) ?? -1, target: self, action: #selector(setReminder(_:))), width: w),
            UI.row("Send the pet home", nil, Btn("Send home", target: self, action: #selector(sendHome)), width: w),
        ], width: w)

        let cli = UI.group("Command line", [
            UI.row("gremlo", "Talk to the pet from any terminal.", Btn("Install", target: self, action: #selector(installCommand)), width: w),
        ], width: w)
        let quit = UI.group("Gremlo", [
            UI.row("Quit Gremlo", "The pet and its hook server stop until you open Gremlo again.", Btn("Quit", target: self, action: #selector(quitApp)), width: w),
        ], width: w)
        return [claude, screen, cli, quit]
    }

    // MARK: Pet

    func petGroups() -> [NSView] {
        let w = pageWidth
        let cols = 4, gap: CGFloat = 10
        let tileW = (w - gap * CGFloat(cols - 1)) / CGFloat(cols)
        var rows: [NSView] = []
        var current: [NSView] = []
        for (i, sp) in Roster.all.enumerated() {
            current.append(SpeciesTile(species: sp, frame: Backend.idleFrame(sp.id), lock: speciesLock(sp.id), chosen: sp.id == pet.skin.name,
                                       open: demoMode, index: i, width: tileW, target: self, action: #selector(pickSpecies(_:))))
            if current.count == cols { rows.append(UI.hstack(current, spacing: gap, align: .top)); current = [] }
        }
        if !current.isEmpty { rows.append(UI.hstack(current, spacing: gap, align: .top)) }
        let grid = UI.vstack([UI.padLeft(UI.caption("Species"), 14)] + rows, spacing: gap)
        let growing = UI.group("Growing up", [
            UI.row("Closet, stars and certificate", "Earned outfits, the room, tricks and the diary.", Btn("Open", target: self, action: #selector(openGrowth)), width: w),
            UI.row("Pet page", "This week's recap, with the receipts.", Btn("Open", target: self, action: #selector(openPetPage)), width: w),
        ], width: w)
        return [nameGroup(), grid, growing]
    }

    private static var nameNote: String?
    /// The pet's name, saved in defaults (GREMLO_PET still wins). It is read once at launch, so a new name restarts the app.
    func nameGroup() -> NSView {
        let w = pageWidth
        let fromEnv = Legacy.env("PET") != nil
        let field = Field(petName, placeholder: "mochi", width: 200)
        field.target = self
        field.action = #selector(setPetName(_:))
        field.cell?.sendsActionOnEndEditing = false // only Return saves: clicking away mustn't restart the app
        field.isEnabled = !fromEnv
        let note = fromEnv ? "Set by GREMLO_PET, which wins over this field." : Self.nameNote ?? "The pet this Mac shows and earns for. Press Return to save; Gremlo restarts to switch."
        return UI.group("Name", [UI.row("Pet name", note, field, width: w)], width: w)
    }

    @objc func setPetName(_ f: NSTextField) {
        guard let name = PetName.clean(f.stringValue) else {
            Self.nameNote = "\u{201C}\(f.stringValue)\u{201D} isn't a pet name: 2-24 of a-z, 0-9 and dashes, not starting or ending with a dash."
            NSSound.beep()
            settings.reload()
            return
        }
        Self.nameNote = nil
        guard name != petName else { settings.reload(); return }
        defaults.set(name, forKey: PetName.defaultsKey)
        // relaunching needs a bundle; `swift run` just says so
        guard Bundle.main.bundleIdentifier != nil else {
            Self.nameNote = "Saved as \(name). Quit and start Gremlo again to switch."
            settings.reload()
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path] // after this copy has let go of the hook port
        try? p.run()
        NSApp.terminate(nil)
    }

    private static var idleFrames: [String: CGImage] = [:]
    /// One idle frame per species for the picker, loaded once.
    static func idleFrame(_ id: String) -> CGImage? {
        if let f = idleFrames[id] { return f }
        let f = loadSkin(id: id).flatMap { ($0.strips[.idle] ?? $0.strips[.walk])?.frames.first }
        idleFrames[id] = f
        return f
    }

    @objc func pickSpecies(_ b: NSButton) {
        guard Roster.all.indices.contains(b.tag) else { return }
        let sp = Roster.all[b.tag]
        guard speciesLock(sp.id) == nil || demoMode || sp.id == pet.skin.name, let s = loadSkin(id: sp.id) else { return }
        if !demoMode { defaults.set(sp.id, forKey: "skin") }  // a demo preview isn't saved
        pet.setSkin(s)
        UI.setAccent(s.species)
        Feel.haptic(.tick)
        shown = ""
        render()
        settings.reload()
    }

    // MARK: Earning

    func earningGroups() -> [NSView] {
        let w = pageWidth
        var rows = [
            UI.row("Show sponsored lines", "The pet holds one short line while your agent works. Brands pay per verified view. Never during an approval, at most 120 a day.",
                   Toggle(on: sponsoredOn, target: self, action: #selector(toggleSponsored(_:)), label: "Show sponsored lines"), width: w),
            UI.row("Quiet hours", "No lines from 22:00 to 08:00.", Toggle(on: quietHours, target: self, action: #selector(toggleQuiet(_:)), label: "Quiet hours"), width: w),
        ]
        if !SocialController.blockedBrands.isEmpty {
            rows.append(UI.row("Hidden brands", SocialController.blockedBrands.joined(separator: ", "), Btn("Show again", target: self, action: #selector(clearBlocked)), width: w))
        }
        return [UI.group("Sponsored line", rows, width: w), costAlertGroup()]
    }

    // MARK: Phone and Mac, developer

    func thisMacGroup() -> NSView {
        let w = pageWidth
        let row = devicePublicKey != nil
            ? UI.row("Pair this Mac with my pet", "Its Secure Enclave signs the pet's views, so nobody else can earn as your pet. You approve it once on the web.",
                     Btn("Pair", target: self, action: #selector(pairDevice)), width: w)
            : UI.row("No Secure Enclave", "Views from this Mac stay unsigned.", nil, width: w)
        return UI.group("This Mac", [row], width: w)
    }

    func demoGroup() -> NSView {
        let w = pageWidth
        return UI.group("Demo", [
            UI.row("Demo controls", "Play any reaction from the menu bar. While demo mode is on there are no AI calls and no paid views.",
                   Btn("Open", target: self, action: #selector(openDemoFromSettings)), width: w),
        ], width: w)
    }
    @objc func openDemoFromSettings() { settings.orderOut(nil); toggle(); openDemo() }
}

/// One species in the picker: its idle frame, name and kind, or what unlocks it. The whole tile is the button.
final class SpeciesTile: NSButton {
    private let box: Box
    private let chosen: Bool
    private var hovering = false { didSet { box.fill = chosen ? UI.control : (hovering ? UI.controlHover : UI.surface) } }

    init(species sp: Species, frame img: CGImage?, lock: String?, chosen: Bool, open: Bool, index: Int, width: CGFloat, target: AnyObject?, action: Selector?) {
        self.chosen = chosen
        box = Box(fill: chosen ? UI.control : UI.surface, radius: 12, stroke: chosen ? UI.accent : nil)
        super.init(frame: .zero)
        isBordered = false
        title = ""
        tag = index
        self.target = target
        self.action = action
        let usable = lock == nil || open || chosen
        isEnabled = usable
        let art = NSView()
        art.wantsLayer = true
        art.layer?.contents = img
        art.layer?.contentsGravity = .resizeAspect
        art.layer?.magnificationFilter = .nearest
        UI.fixed(art, w: 58, h: 62)
        let detail = lock.map { "unlocks with \($0)" } ?? "the \(sp.kind)"
        let note = UI.label(detail, UI.body(10), UI.text2, width: width - 20)
        note.alignment = .center
        let words = UI.vstack([UI.label(sp.name, UI.body(13, .semibold), UI.fg, wrap: false), note], spacing: 2)
        words.alignment = .centerX
        let s = UI.vstack([art, words], spacing: 6, insets: NSEdgeInsets(top: 12, left: 8, bottom: 12, right: 8))
        s.alignment = .centerX
        s.translatesAutoresizingMaskIntoConstraints = false
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(s)
        addSubview(box)
        NSLayoutConstraint.activate([box.topAnchor.constraint(equalTo: topAnchor), box.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     box.leadingAnchor.constraint(equalTo: leadingAnchor), box.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     s.topAnchor.constraint(equalTo: box.topAnchor), s.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                                     s.leadingAnchor.constraint(equalTo: box.leadingAnchor), s.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                                     widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: 150)])
        alphaValue = usable ? 1 : 0.45
        toolTip = lock.map { "\(sp.name) unlocks with \($0)" }
        setAccessibilityLabel("\(sp.name), \(detail)\(chosen ? ", chosen" : "")")
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ p: NSPoint) -> NSView? { frame.contains(p) ? self : nil }
    override func mouseEntered(with e: NSEvent) { if isEnabled { hovering = true } }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {}
}

/// A full-width row that opens something: a title, an optional detail, a chevron.
final class LinkRow: NSButton {
    private let bg = Box(fill: nil)
    init(_ title: String, detail: String? = nil, width: CGFloat, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        isBordered = false
        self.title = ""
        self.target = target
        self.action = action
        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        chevron.contentTintColor = UI.text3
        let words = UI.vstack([UI.label(title, UI.body(13, .medium), UI.fg, wrap: false)] + (detail.map { [UI.label($0, UI.body(11), UI.text2, wrap: false)] } ?? []), spacing: 2)
        let r = UI.hstack([words, UI.spacer(), chevron], spacing: 8)
        r.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 12)
        for v in [bg, r] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([bg.topAnchor.constraint(equalTo: topAnchor), bg.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     bg.leadingAnchor.constraint(equalTo: leadingAnchor), bg.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     r.topAnchor.constraint(equalTo: topAnchor), r.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     r.leadingAnchor.constraint(equalTo: leadingAnchor), r.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     widthAnchor.constraint(equalToConstant: width)])
        setAccessibilityLabel(title)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ p: NSPoint) -> NSView? { frame.contains(p) ? self : nil }
    override func mouseEntered(with e: NSEvent) { bg.fill = UI.control }
    override func mouseExited(with e: NSEvent) { bg.fill = nil }
    override func draw(_ dirtyRect: NSRect) {}
}
