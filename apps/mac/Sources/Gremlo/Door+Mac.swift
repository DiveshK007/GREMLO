import AppKit

// The door is the notch itself. This panel is only the spot the pet leaves from and comes back to.
// On a display with a camera housing, the notch draws the opening. On any other display, this panel is the pill.

extension Notification.Name {
    static let gremloPetMouth = Notification.Name("gremlo.petMouth")
}

enum DoorState: String, CaseIterable { case closed, glowing, open, locked }

final class Door {
    let size = CGSize(width: 48, height: 10)
    let panel: NSPanel
    var state = DoorState.closed
    /// The screen the pet currently lives on. The built-in display until it is carried to another one.
    private(set) var host: NSScreen?
    private let pill = CALayer()
    private let room = CALayer()

    func setAccent(_ c: CGColor) { _ = c }

    init(art: [DoorState: CGImage], scale: CGFloat, accent: CGColor) {
        _ = (art, scale, accent)
        panel = overlayPanel(size, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        panel.contentView?.wantsLayer = true
        pill.backgroundColor = NSColor.black.cgColor
        pill.cornerRadius = 5
        room.backgroundColor = NSColor(srgbRed: 0.36, green: 0.20, blue: 0.12, alpha: 1).cgColor
        room.cornerRadius = 4
        panel.contentView?.layer?.addSublayer(pill)
        pill.addSublayer(room)
        place(on: mainScreen)
        panel.orderFrontRegardless()
    }

    var hardware: Bool { (host?.safeAreaInsets.top ?? 0) > 0 }

    /// The lip of the housing, centred on `screen`. A display with no camera gets a pill at the top edge.
    func place(on screen: NSScreen) {
        host = screen
        var midX = screen.frame.midX
        let notch = screen.safeAreaInsets.top
        if notch > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            midX = (left.maxX + right.minX) / 2
        }
        let h = panel.frame.height
        let y = notch > 0 ? screen.frame.maxY - notch - 2 : screen.visibleFrame.maxY - h
        panel.setFrame(NSRect(x: midX - size.width / 2, y: y, width: size.width, height: h), display: false)
        layoutPill(open: state == .open)
    }

    var center: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    func open() {
        guard state != .open else { return }
        state = .open
        SoundKit.shared.play(.pop, pan: 0, gain: 0.55)
        if hardware {
            NotificationCenter.default.post(name: .gremloPetMouth, object: nil, userInfo: ["open": true])
        } else {
            layoutPill(open: true)
        }
    }

    func close(lock: Bool) {
        state = lock ? .locked : .closed
        SoundKit.shared.play(.close, pan: 0, gain: 0.32)
        if hardware {
            NotificationCenter.default.post(name: .gremloPetMouth, object: nil, userInfo: ["open": false])
        } else {
            layoutPill(open: false)
        }
    }

    /// The pill hangs down from a fixed top edge. A real notch draws its own opening, so the pill stays hidden.
    private func layoutPill(open: Bool) {
        guard host != nil else { return }
        let top = panel.frame.maxY
        let h: CGFloat = hardware ? size.height : (open ? 26 : size.height)
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - h, width: size.width, height: h), display: true)
        let bounds = panel.contentView?.bounds ?? .zero
        pill.isHidden = hardware
        pill.frame = bounds
        room.frame = open ? CGRect(x: 6, y: 3, width: bounds.width - 12, height: 12) : .zero
    }
}
