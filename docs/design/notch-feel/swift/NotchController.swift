// NotchController.swift · states, sizes, choreography, gestures. Reference code (macOS 14 SDK), not compiled here.
// Implements ideas 1–11 and 26 from NOTCH_FEEL.md. Sizes are points at the default notch width (190 pt);
// scale them by the real notch width from NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea.

import AppKit

enum NotchMode: Equatable {
    case rest, hover, think, open, approval, done, fail, merge, drop, gulp(String), room, volume, battery, charging, screenshot, music, quick, peekOut(PetRow), trick(PetRow), typing

    var size: (w: CGFloat, h: CGFloat, r: CGFloat) {
        switch self {
        case .rest: (190, 32, 12)        case .hover: (236, 38, 14)      case .think: (214, 34, 13)
        case .open: (560, 168, 28)       case .approval: (440, 140, 28)  case .done, .fail, .merge, .music: (330, 44, 18)
        case .drop: (320, 92, 30)        case .gulp: (300, 46, 18)       case .room: (680, 330, 34)
        case .volume: (330, 60, 20)      case .battery, .screenshot: (300, 44, 18)  case .charging: (300, 52, 20)
        case .quick: (460, 62, 24)       case .peekOut: (240, 46, 18)    case .trick: (260, 56, 20)  case .typing: (250, 40, 16)
        }
    }
    var isBig: Bool { [.open, .approval, .room, .quick, .drop].contains(self) }
    var rim: NotchLayer.RimMode { switch self { case .think: .flow; case .approval, .open, .done, .merge, .fail, .battery, .charging: .solid; default: .off } }
}

final class NotchController {
    let layer: NotchLayer
    let W = Spring(190), H = Spring(32), R = Spring(12)
    let lean = Spring(0, .lean), squash = Spring(0, .squash), press = Spring(1, .press), pull = Spring(0, .pull), open = Spring(0, .close)

    private(set) var mode: NotchMode = .rest
    var base: NotchMode = .rest                 // where transient states return to
    private var backTimer: Timer?

    init(layer: NotchLayer) {
        self.layer = layer
        NotchDriver.shared.register(W, H, R, lean, squash, press, pull, open)
        NotchDriver.shared.onFrame = { [weak self] in self?.applyFrame() }
    }

    // MARK: 1–3 · springs, squash/stretch, staggered content
    func go(_ m: NotchMode, back after: TimeInterval? = nil) {
        backTimer?.invalidate()
        let was = mode; mode = m
        let s = m.size
        let opening = s.w * s.h > W.value * H.value + 200
        let p: SpringParams = opening ? .open : .close
        W.animate(to: s.w, p, onPeak: opening ? { Haptics.shared.play(.snap, at: .drawCompleted) } : nil)   // #19 tap on the overshoot frame
        H.animate(to: s.h, SpringParams(response: p.response + 0.03, damping: p.damping))
        R.animate(to: s.r, SpringParams(response: 0.4, damping: 0.9))
        open.animate(to: m.isBig ? 1 : 0)
        if !Motion.reduce { squash.kick(opening ? -2.2 : 1.4) }                                         // #2 jelly
        if opening { SoundKit.shared.play(.pop) } else if was.isBig && !m.isBig { SoundKit.shared.play(.close) }
        layer.rimMode = m.rim
        ContentStack.shared.replace(with: m, stagger: Motion.reduce ? 0 : 0.045, firstDelay: Motion.reduce ? 0 : 0.06)   // #3
        Particles.shared.react(to: m, from: layer)                                                       // #14
        if let after { backTimer = .scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in guard let self else { return }; self.go(self.base) } }
    }

    private func applyFrame() {
        let g = NotchGeometry(width: W.value, height: H.value + max(0, pull.value), radius: R.value, bulge: max(0, -squash.value) / 2.2)
        layer.apply(g, lean: lean.value, squash: squash.value, press: press.value, expanded: open.value)
    }

    // MARK: 4 · lean toward the cursor (global mouse-moved monitor: mouse events need no permission)
    func cursorMoved(to p: CGPoint, notchCenter c: CGPoint) {
        guard [.rest, .think, .hover].contains(mode) else { return }
        let dx = p.x - c.x, dy = c.y - p.y                    // AppKit y grows upward
        let d = hypot(dx * 0.6, dy), near = max(0, 1 - d / 140)
        lean.animate(to: max(-1, min(1, dx / 200)) * 8 * near)
        if d < 34, mode != .hover { go(.hover); Haptics.shared.play(.tick) }
        else if d > 70, mode == .hover { go(base) }
        else if mode != .hover { let s = mode.size; W.animate(to: s.w + 18 * near, .lean); H.animate(to: s.h + 4 * near, .lean) }
    }

    // MARK: 5, 7 · press dent, rubber band, flick
    private var dragStartY: CGFloat = 0, overThreshold = false, velocityY: CGFloat = 0
    func mouseDown(at y: CGFloat) {
        press.animate(to: 0.955, .press); Haptics.shared.play(.boop)
        dragStartY = y; overThreshold = false
    }
    func mouseDragged(to y: CGFloat, velocity v: CGFloat) {
        velocityY = v
        let dy = dragStartY - y                                    // downward pull, AppKit coords
        guard dy > 0 else { return }
        let band = dy * 0.55 / (1 + dy / 320) * 2                  // rubber band: follows, then resists
        pull.hold(at: band); NotchDriver.shared.wake()
        let over = band > 130
        if over != overThreshold { overThreshold = over; Haptics.shared.play(.tick) }   // a tick each way across the line
    }
    func mouseUp(clickCount: Int) {
        press.animate(to: 1, .release)
        if overThreshold { pull.animate(to: 0, .pull); go(.room); Haptics.shared.play(.snap); return }
        if pull.value > 1 { pull.animate(to: 0, .pull) }
        if velocityY > 500, mode.isBig { SoundKit.shared.play(.whoosh); go(base); return }   // flick up dismisses
        if clickCount >= 3 { trick(); return }                      // #26
        if clickCount == 1 { mode.isBig ? go(base) : go(.open) }
    }

    // MARK: 8 · two-finger scroll switches agents with detents
    private var scrollAccum: CGFloat = 0
    func scrolled(_ e: NSEvent) {
        guard mode == .open else { return }
        scrollAccum += e.scrollingDeltaX != 0 ? e.scrollingDeltaX : e.scrollingDeltaY
        if abs(scrollAccum) > 40 { let dir = scrollAccum > 0 ? 1 : -1; scrollAccum = 0; Agents.shared.select(offset: dir); Haptics.shared.play(.tick); SoundKit.shared.play(.tick) }
        if e.phase == .ended || e.momentumPhase == .ended { scrollAccum = 0 }
    }

    // MARK: 9 · force click → quick actions (the trackpad clicks physically at stage 2; add no extra tap)
    func pressureChanged(_ e: NSEvent) {
        if e.stage == 2, mode != .quick { go(.quick); SoundKit.shared.play(.boing) }
        else if e.stage == 1 { press.animate(to: 1 - 0.04 * CGFloat(e.pressure), .press) }   // pressure deepens the dent
    }

    // MARK: 11 · keyboard (global shortcut registered with the app's hotkey helper)
    func key(_ k: KeyCommand) {
        switch k {
        case .toggle: mode.isBig ? go(base) : go(.open); Haptics.shared.play(.tick)
        case .left, .right: if mode == .approval { Approvals.shared.moveSelection(k == .left ? -1 : 1); Haptics.shared.play(.tick) } else if mode == .open { Agents.shared.select(offset: k == .left ? -1 : 1) }
        case .enter: if mode == .approval { Approvals.shared.confirmSelection() }
        case .escape: go(base)
        }
    }
    enum KeyCommand { case toggle, left, right, enter, escape }

    // MARK: 26 · easter eggs
    func trick() {
        let row = [PetRow.backflip, .juggle, .moonwalk].randomElement()!
        go(.trick(row), back: 2.4); Haptics.shared.play(.snap); SoundKit.shared.play(.boing)
    }
}
