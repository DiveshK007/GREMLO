import GremloCore
import AppKit
import CryptoKit
import Network
import UserNotifications

// The hidden door under the notch (moved out of main.swift unchanged).

enum DoorState: String, CaseIterable { case closed, glowing, open, locked }

// A hidden arched door under the notch. Invisible at rest so the notch looks stock; it only appears while
// the pet crosses: fade + scale in (55% to 100%), Signal glow, leaf swings open to the right, then closes and fades.
// Uses the pet's door_<state>.png art instead of the drawn leaf if it has all four.
final class Door {
    let size: CGSize
    let art: [DoorState: CGImage]
    let panel: NSPanel
    let body = CALayer()
    let glow = CAShapeLayer()
    let leaf = CAShapeLayer()
    let lockBody = CAShapeLayer()
    let lockShackle = CAShapeLayer()
    let artLayer = CALayer()
    var state = DoorState.closed
    /// The active pet lends the door its glow.
    func setAccent(_ c: CGColor) { glow.fillColor = c; glow.shadowColor = c }
    var gen = 0  // bumps on every open/close so a stale animation step can't reopen the door

    init(art: [DoorState: CGImage], scale: CGFloat, accent: CGColor) {
        self.art = art
        size = art[.closed].map { CGSize(width: CGFloat($0.width) * scale, height: CGFloat($0.height) * scale) } ?? CGSize(width: 14, height: 18)
        panel = overlayPanel(size, level: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1))
        let bounds = CGRect(origin: .zero, size: size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: 0.5))
        path.addLine(to: CGPoint(x: size.width - 0.5, y: 0.5))
        path.addLine(to: CGPoint(x: size.width - 0.5, y: size.height - size.width / 2))
        path.addArc(center: CGPoint(x: size.width / 2, y: size.height - size.width / 2),
                    radius: size.width / 2 - 0.5, startAngle: 0, endAngle: .pi, clockwise: false)
        path.closeSubpath()
        body.frame = bounds
        glow.frame = bounds
        glow.path = path
        glow.fillColor = accent
        glow.shadowColor = accent
        glow.shadowRadius = 5
        glow.shadowOffset = .zero
        glow.shadowOpacity = 1
        glow.opacity = 0
        leaf.anchorPoint = CGPoint(x: 1, y: 0.5)  // hinge on the right edge
        leaf.frame = bounds
        leaf.path = path
        leaf.fillColor = CGColor(gray: 0, alpha: 1)
        leaf.strokeColor = CGColor(gray: 1, alpha: 0.16)
        leaf.lineWidth = 1
        let mid = size.width / 2
        lockBody.path = CGPath(rect: CGRect(x: mid - 3, y: 4, width: 6, height: 5), transform: nil)
        lockBody.fillColor = paperColor
        let shackle = CGMutablePath()
        shackle.addArc(center: CGPoint(x: mid, y: 9), radius: 2, startAngle: 0, endAngle: .pi, clockwise: false)
        lockShackle.path = shackle
        lockShackle.fillColor = nil
        lockShackle.strokeColor = paperColor
        lockShackle.lineWidth = 1
        artLayer.frame = bounds
        artLayer.magnificationFilter = .nearest
        artLayer.contentsGravity = .resizeAspect
        let parts = art.isEmpty ? [glow, leaf, lockBody, lockShackle] : [artLayer]
        for layer in parts { body.addSublayer(layer) }
        panel.contentView?.layer?.addSublayer(body)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hide()
        showLock(false)
        CATransaction.commit()
        place()
        panel.orderFrontRegardless()
    }

    // Bottom centre of the notch; top centre under the menu bar on Macs without one.
    func place() {
        let screen = mainScreen
        var midX = screen.frame.midX
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            midX = (left.maxX + right.minX) / 2
        }
        panel.setFrameOrigin(NSPoint(x: midX - size.width / 2, y: screen.visibleFrame.maxY - size.height))
    }

    var center: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    func log(_ s: DoorState) {
        if s != state { print("door \(state.rawValue) -> \(s.rawValue)") }
        state = s
    }

    func hide() {
        body.opacity = 0
        body.transform = CATransform3DMakeScale(0.55, 0.55, 1)
    }

    func showLock(_ on: Bool) {
        lockBody.isHidden = !on
        lockShackle.isHidden = !on
        if !art.isEmpty, on { artLayer.contents = art[.locked] }
    }

    // One eased step; `then` runs only if no newer open/close started meanwhile.
    func step(_ seconds: Double, _ g: Int, _ change: () -> Void, then: (() -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(seconds)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self] in if self?.gen == g { then?() } }
        change()
        CATransaction.commit()
    }

    // Appear, glow, swing open. About 0.26s.
    func open() {
        gen += 1
        let g = gen
        if state != .open { Feel.event("door.open") }
        log(.open)
        showLock(false)
        artLayer.contents = art[.closed]
        step(0.12, g, { body.opacity = 1; body.transform = CATransform3DIdentity }) {
            self.artLayer.contents = self.art[.glowing]
            self.step(0.06, g, { self.glow.opacity = 1 }) {
                self.artLayer.contents = self.art[.open]
                self.step(0.08, g, { self.leaf.transform = CATransform3DMakeScale(0.12, 1, 1) })
            }
        }
    }

    // Swing shut, show the padlock for a beat if locking, then fade and shrink away. About 0.14s, 0.5s with the lock.
    func close(lock: Bool) {
        gen += 1
        let g = gen
        if state == .open { Feel.event("door.close") }
        log(lock ? .locked : .closed)
        artLayer.contents = art[.closed]
        step(0.08, g, { leaf.transform = CATransform3DIdentity; glow.opacity = 0; body.opacity = 1; body.transform = CATransform3DIdentity }) {
            self.showLock(lock)
            self.step(lock ? 0.35 : 0.0, g, {}) {
                self.step(0.12, g, { self.hide() }) { self.showLock(false) }
            }
        }
    }
}
