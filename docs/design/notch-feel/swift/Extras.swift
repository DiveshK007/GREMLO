// Extras.swift · ideas 6, 10, 12, 15, 16, 18, 25, 27. Reference code, not compiled here.

import AppKit

// MARK: 12 · drop zone with a mouth
// The notch panel registers for file and image drags. Entering opens .drop (pet mouth open), dropping gulps.
// Clipboard gets the paths (quoted if they contain spaces) and, for images, the image too. Nothing is uploaded.
final class NotchDropView: NSView {
    weak var notch: NotchController?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL, .png, .tiff, .string]) }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { notch?.go(.drop); Haptics.shared.play(.snap); return .copy }
    override func draggingExited(_ s: NSDraggingInfo?) { if let n = notch { n.go(n.base) }; Haptics.shared.play(.tick) }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        let pb = NSPasteboard.general; pb.clearContents()
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        if !urls.isEmpty {
            pb.setString(urls.map { $0.path.contains(" ") ? "\"\($0.path)\"" : $0.path }.joined(separator: "\n"), forType: .string)
            if urls.count == 1, let img = NSImage(contentsOf: urls[0]) { pb.writeObjects([img]) }   // agents that accept pasted images get it
        } else if let str = s.draggingPasteboard.string(forType: .string) { pb.setString(str, forType: .string) }
        SoundKit.shared.play(.chomp); Haptics.shared.play(.boop)
        notch?.go(.gulp(urls.count > 1 ? "\(urls.count) paths copied" : "Ready to paste"), back: 2.6)
        return true
    }
}

// MARK: 10 · fling the pet out of the notch
// Dragging the pet in .open/.room spawns it in its own borderless, transparent, non-activating panel.
// Release velocity carries it; gravity 2200 pt/s²; it bounces off the visibleFrame floor (above the Dock),
// thuds (haptic only if the finger is still down), sits 1.8 s, walks back and climbs in.
final class FreePet {
    var pos: CGPoint, vel: CGVector = .zero, held = true, walkingHome = false
    let panel: NSPanel
    init(at p: CGPoint) {
        pos = p
        panel = NSPanel(contentRect: NSRect(x: p.x, y: p.y, width: 80, height: 88), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.orderFrontRegardless()
        NotchDriver.shared.addTicker { [weak self] dt in self?.step(dt) ?? false }
    }
    func release(velocity v: CGVector) { held = false; vel = v; SoundKit.shared.play(.whoosh) }
    private func step(_ dt: Double) -> Bool {
        guard !held, let screen = NSScreen.main else { return true }
        let floor = screen.visibleFrame.minY, home = CGPoint(x: screen.frame.midX - 40, y: screen.frame.maxY - 60)
        if walkingHome {
            let dx = home.x - pos.x; pos.x += CGFloat(dx.sign == .minus ? -1 : 1) * min(abs(dx), 140 * dt)
            if abs(dx) < 2 { panel.close(); NotchCenter.shared.go(.gulp("Mochi is home"), back: 2.6); Haptics.shared.play(.boop); return false }
        } else {
            vel.dy -= 2200 * dt; pos.x += vel.dx * dt; pos.y += vel.dy * dt; vel.dx *= 0.995
            if pos.y <= floor { pos.y = floor; if abs(vel.dy) > 240 { vel.dy *= -0.35; vel.dx *= 0.7; Haptics.shared.play(.thud); SoundKit.shared.play(.thud) } else { vel = .zero; land() } }
        }
        panel.setFrameOrigin(pos)
        return true
    }
    private var landed = false
    private func land() { guard !landed else { return }; landed = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.walkingHome = true } }
    // Walking home: the pet walks along the floor to under the notch, then plays the climb row (2) up the screen edge; the panel follows.
}

// MARK: 16 · idle life
// Every 20–40 s while the notch is at rest and the screen is awake: one small action. Never during a share, a meeting,
// or Focus, never more than ~2 a minute.
final class IdleLife {
    private var timer: Timer?
    func start(_ notch: NotchController) {
        schedule(notch)
    }
    private func schedule(_ notch: NotchController) {
        timer = .scheduledTimer(withTimeInterval: .random(in: 20...40), repeats: false) { [weak self] _ in
            if notch.mode == .rest, !ScreenShare.isActive, !Focus.isOn { notch.go(.peekOut([.yawn, .peek, .edgepeek, .gaze].randomElement()!), back: 2.2) }
            self?.schedule(notch)
        }
        timer?.tolerance = 3
    }
}

// MARK: 6 · the pet looks at the cursor
// In peek rows, flip the sprite toward the cursor (x < notch centre − 30 → face left). Cheap: changes only on a side change.

// MARK: 15 · progress as a scene
// In .open, a 54 pt track: fill = run progress (from hook events / ETA), the walk-row pet stands at the fill edge.
// Unknown ETA: the pet walks in place at the left and the fill pulses; never a made-up percentage.

// MARK: 18 · rolling numbers
// Each digit is a column 0–9 in a clipped 14 pt cell; changes animate translateY with the .release spring.
// Use SF Mono / JetBrains Mono with tabular figures so widths never jump.

// MARK: 25 · typing pace (opt-in)
// Needs Accessibility trust (NSEvent global keyDown monitor). Stores only timestamps of the last 1.5 s; never key codes.
final class TypingPace {
    private var stamps: [TimeInterval] = []
    private var monitor: Any?, nap: Timer?
    func start(_ notch: NotchController) {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return }
            let now = e.timestamp; self.stamps.append(now); self.stamps.removeAll { now - $0 > 1.5 }
            let cps = Double(self.stamps.count) / 1.5
            if cps > 6, notch.mode == .rest { notch.go(.typing, back: 1.8) }
            self.nap?.invalidate()
            self.nap = .scheduledTimer(withTimeInterval: 300, repeats: false) { _ in if notch.mode == .rest { notch.go(.peekOut(.night), back: 2.6) } }
        }
    }
    func stop() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil; stamps = [] }
}

// MARK: 27 · bops to your music (opt-in)
// Public route: AppleScript to Music and Spotify (needs NSAppleEventsUsageDescription + the user's Automation consent),
// polled every 5 s only while enabled. No beat detection: a steady 2 Hz bop while playing. MediaRemote (private) is NOT used,
// so this stays App Store-safe.
final class NowPlaying {
    private var timer: Timer?
    func start(_ notch: NotchController) {
        timer = .scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            let script = """
            if application "Music" is running then tell application "Music" to if player state is playing then return name of current track
            if application "Spotify" is running then tell application "Spotify" to if player state is playing then return name of current track
            return ""
            """
            var err: NSDictionary?
            let title = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue ?? ""
            if !title.isEmpty { MusicRow.title = title; if notch.mode == .rest { notch.base = .music; notch.go(.music) } }
            else if notch.base == .music { notch.base = .rest; notch.go(.rest) }
        }
        timer?.tolerance = 1
    }
}
