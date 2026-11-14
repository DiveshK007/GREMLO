import AppKit

// The door is the notch itself. This panel is only the spot the pet leaves from and comes back to:
// the lip of the camera housing. The notch draws the opening.

extension Notification.Name {
    static let gremloPetMouth = Notification.Name("gremlo.petMouth")
}

enum DoorState: String, CaseIterable { case closed, glowing, open, locked }

final class Door {
    let size = CGSize(width: 48, height: 10)
    let panel: NSPanel
    var state = DoorState.closed

    func setAccent(_ c: CGColor) { _ = c }

    init(art: [DoorState: CGImage], scale: CGFloat, accent: CGColor) {
        _ = (art, scale, accent)
        panel = overlayPanel(size, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        place()
        panel.orderFrontRegardless()
    }

    /// The lip of the housing, centred. The pet drops from here and climbs back to here.
    func place() {
        let screen = mainScreen
        var midX = screen.frame.midX
        let notch = screen.safeAreaInsets.top
        if notch > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            midX = (left.maxX + right.minX) / 2
        }
        let y = notch > 0 ? screen.frame.maxY - notch - 2 : screen.visibleFrame.maxY - size.height
        panel.setFrameOrigin(NSPoint(x: midX - size.width / 2, y: y))
    }

    var center: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    func open() {
        guard state != .open else { return }
        state = .open
        SoundKit.shared.play(.pop)
        NotificationCenter.default.post(name: .gremloPetMouth, object: nil, userInfo: ["open": true])
    }

    func close(lock: Bool) {
        state = lock ? .locked : .closed
        SoundKit.shared.play(.close)
        NotificationCenter.default.post(name: .gremloPetMouth, object: nil, userInfo: ["open": false])
    }
}
