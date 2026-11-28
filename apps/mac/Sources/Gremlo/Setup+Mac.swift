import AppKit
import GremloCore

// First run (Setup in GremloCore holds the steps and the messages): welcome, your pet, pair this Mac, connect
// Claude Code, and a test event the pet answers. Every failure says why and offers Retry. Shown once; Settings,
// General runs it again.
final class SetupWindow: NSWindow, NSWindowDelegate {
    unowned let backend: Backend
    private(set) var step = Setup.Step.welcome
    private var name: String
    private var problem: String?
    private var busy = false
    private var heard = false
    private var paired: Bool?
    private let field: Field
    private let width: CGFloat = 440

    init(backend: Backend) {
        self.backend = backend
        name = defaults.string(forKey: PetName.defaultsKey) ?? ""
        field = Field(name, placeholder: "your pet's name", width: 260)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "Set up \(productName)"
        isReleasedWhenClosed = false
        backgroundColor = UI.bg
        delegate = self
        field.target = self
        field.action = #selector(usePet)
        field.setAccessibilityLabel("Pet name")
    }

    func show() {
        step = .welcome; problem = nil
        render()
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { defaults.set(true, forKey: "setupDone") }

    /// The test event arrived at the hook server: the pet comes out, then celebrates.
    func heardTest() {
        heard = true
        if backend.pet.egg { backend.pet.comeOut(then: .hatch) } else { backend.pet.handle(event: "UserPromptSubmit", notification: nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.backend.pet.egg == false { self?.backend.pet.handle(event: "Stop", notification: nil) }
        }
    }

    // MARK: steps

    @objc func start() { go(.pet) }
    @objc func later() { close() }

    @objc func getPet() {
        let web = Legacy.env("WEB") ?? "https://gremlo.vercel.app"
        if let u = URL(string: "\(web)/pet") { NSWorkspace.shared.open(u) }
    }

    @objc func usePet() {
        guard let n = PetName.clean(field.stringValue) else {
            problem = "\u{201C}\(field.stringValue)\u{201D} isn't a pet name: 2 to 24 of a-z, 0-9 and dashes, not starting or ending with a dash."
            return render()
        }
        name = n
        lookUp { [weak self] err in
            guard let self else { return }
            self.problem = Setup.petProblem(name: n, error: err)
            if self.problem == nil { self.go(.pair) } else { self.render() }
        }
    }

    @objc func pair() {
        guard let key = devicePublicKey else { return }
        let web = Legacy.env("WEB") ?? "https://gremlo.vercel.app"
        let pet = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        if let u = URL(string: "\(web)/pair?pet=\(pet)&key=\(key)") { NSWorkspace.shared.open(u) }
        problem = nil
        render()
    }

    @objc func checkPair() {
        lookUp { [weak self] err in
            guard let self else { return }
            self.problem = Setup.pairProblem(secureEnclave: devicePublicKey != nil, paired: self.paired, error: err)
            if self.problem == nil { self.go(.claude) } else { self.render() }
        }
    }

    @objc func skipPair() { go(.claude) }

    @objc func connect() {
        do {
            if !ClaudeHooks.isConnected { try ClaudeHooks.connect() }
            go(.test)
        } catch {
            problem = "Couldn't update ~/.claude/settings.json: \(error.localizedDescription) Nothing was changed. Fix the file, then press Retry."
            render()
        }
    }

    @objc func runTest() {
        heard = false
        busy = true
        problem = nil
        render()
        let fm = FileManager.default, script = ClaudeHooks.scriptURL
        let header = script.deletingLastPathComponent().appendingPathComponent("hook-header")
        let ready = (ClaudeHooks.isConnected, fm.fileExists(atPath: script.path), fm.fileExists(atPath: header.path))
        let finish = { [weak self] (code: Int32?) in
            guard let self else { return }
            self.busy = false
            self.problem = Setup.testProblem(connected: ready.0, scriptExists: ready.1, headerExists: ready.2, heard: self.heard, exitCode: code)
            if self.problem == nil { self.go(.done) } else { self.render() }
        }
        guard ready.0, ready.1, ready.2 else { return finish(nil) }
        // the same path a Claude Code event takes: the installed script, its key file, the hook server
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { proc in
            // the script posts fire-and-forget; give the server a moment to hand the event over
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { finish(proc.terminationStatus) }
        }
        do { try p.run() } catch { return finish(127) }
        input.fileHandleForWriting.write(Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"\#(Setup.testSession)"}"#.utf8))
        try? input.fileHandleForWriting.close()
    }

    @objc func finish() {
        defaults.set(true, forKey: "setupDone")
        close()
        guard name != backend.petName, !name.isEmpty, Legacy.env("PET") == nil else { return backend.askSponsoredOnce() }
        defaults.set(name, forKey: PetName.defaultsKey)
        // the pet name is read once at launch; the fresh copy asks about sponsored lines
        if Bundle.main.bundleIdentifier != nil { backend.relaunch() }
    }

    private func go(_ s: Setup.Step) { step = s; problem = nil; render() }

    /// GET /pets/<name> for this Mac's key: nil error when the server knows the pet; `paired` from its answer.
    private func lookUp(_ done: @escaping (String?) -> Void) {
        busy = true
        render()
        let path = "/pets/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name) + (devicePublicKey.map { "?device=\($0)" } ?? "")
        backend.request(path) { [weak self] data, err in
            guard let self else { return }
            self.busy = false
            let o = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            self.paired = o?["thisDevicePaired"] as? Bool ?? o?["paired"] as? Bool
            done(err)
        }
    }

    // MARK: drawing

    private func render() {
        let w = width
        var body: [NSView] = []
        var buttons: [NSView] = []
        let primary = { (title: String, action: Selector) -> Btn in
            let b = Btn(title, style: .primary, target: self, action: action); b.keyEquivalent = "\r"; return b
        }
        let other = { (title: String, action: Selector) -> Btn in Btn(title, style: .secondary, target: self, action: action) }
        let text = { (s: String) in body.append(UI.label(s, UI.body(13), UI.text2, width: w)) }
        let heading: String
        switch step {
        case .welcome:
            heading = "\(productName) lives in your notch"
            text("It comes out while Claude Code works, holds one short sponsored line, and waves when the agent needs your approval. Setup takes about two minutes.")
            let l = Btn("Later", style: .ghost, target: self, action: #selector(later)); l.keyEquivalent = "\u{1b}"
            buttons = [l, primary("Start", #selector(start))]
        case .pet:
            heading = "Your pet"
            text("Type your pet's name. No pet yet? Get one on the web, then come back and type its name here.")
            body.append(field)
            buttons = [other("Get a pet", #selector(getPet)), primary(problem == nil ? "Use this pet" : "Retry", #selector(usePet))]
        case .pair:
            heading = "Pair this Mac"
            if devicePublicKey == nil {
                buttons = [primary("Continue", #selector(skipPair))]
                problem = Setup.pairProblem(secureEnclave: false, paired: nil, error: nil)
            } else {
                text("Views count only from a paired Mac. Press Pair, sign once in the browser with the wallet that owns \(name), then press Check.")
                buttons = [Btn("Skip", style: .ghost, target: self, action: #selector(skipPair)), other("Pair", #selector(pair)),
                           primary(problem == nil ? "Check" : "Retry", #selector(checkPair))]
            }
        case .claude:
            heading = "Connect Claude Code"
            text(ClaudeHooks.isConnected ? "Already connected." : "\(productName) adds its hooks to ~/.claude/settings.json and keeps a backup first. Your other hooks stay as they are.")
            buttons = [primary(ClaudeHooks.isConnected ? "Next" : problem == nil ? "Connect" : "Retry", #selector(connect))]
        case .test:
            heading = "Say hello"
            text("This sends one test event through the same hook Claude Code uses. Your pet comes out of the notch when it arrives.")
            buttons = [primary(problem == nil ? "Run the test" : "Retry", #selector(runTest))]
        case .done:
            heading = "All set"
            text("Start Claude Code in any project and \(name.isEmpty ? "your pet" : name) comes out while it works."
                 + (name != backend.petName && !name.isEmpty ? " \(productName) restarts once to switch to \(name)." : ""))
            buttons = [primary("Done", #selector(finish))]
        }
        if let problem { body.append(UI.notice(problem, UI.amber, width: w)) }
        if busy { buttons.forEach { ($0 as? NSButton)?.isEnabled = false } }
        let count = step == .welcome || step == .done ? "" : "Step \(step.rawValue) of 4"
        let row = UI.hstack([UI.caption(busy ? "Checking\u{2026}" : count), UI.spacer()] + buttons, spacing: 8)
        row.widthAnchor.constraint(equalToConstant: w).isActive = true
        let stack = UI.vstack([UI.label(heading, UI.display(30), UI.fg, width: w)] + body + [UI.spacer(), row], spacing: 14,
                              insets: NSEdgeInsets(top: 36, left: 40, bottom: 28, right: 40))
        stack.alignment = .leading
        contentView = stack
        if step == .pet { makeFirstResponder(field) }
    }
}

extension Backend {
    /// First launch: the setup, unless this Mac already used Gremlo (a saved name, hooks, or the sponsored question answered).
    func firstRun() {
        if defaults.bool(forKey: "setupDone") || defaults.string(forKey: PetName.defaultsKey) != nil || ClaudeHooks.isConnected || defaults.object(forKey: "sponsored") != nil {
            defaults.set(true, forKey: "setupDone")
            return askSponsoredOnce()
        }
        setup.show()
    }
    @objc func runSetup() { settings.orderOut(nil); setup.show() }
}
