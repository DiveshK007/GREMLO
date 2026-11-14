// NotchDriver.swift · the frame clock. Reference code (macOS 14 SDK), not compiled here.
//
// Rules (NOTCH_FEEL.md §5):
//  • Springs and particles get every display frame (120 Hz on ProMotion), through a CADisplayLink from the notch view.
//  • The display link is paused the moment nothing moves. Idle = 0 frames, ~0% CPU.
//  • Pet sprites run on their own 8 fps clock, which is also paused while the notch is hidden,
//    the screen is asleep or locked, or a full-screen app owns the display.
//  • Low Power Mode caps the link at 60 Hz and halves particle budgets.

import AppKit
import QuartzCore

final class NotchDriver: NSObject {
    static let shared = NotchDriver()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var springs: [Spring] = []
    private var tickers: [(Double) -> Bool] = []        // particles, free pet… return true while still moving
    var onFrame: (() -> Void)?                          // apply spring values to layers

    func attach(to view: NSView) {
        let l = view.displayLink(target: self, selector: #selector(frame(_:)))
        l.add(to: .main, forMode: .common)
        l.isPaused = true
        link = l
        applyPowerMode()
        NotificationCenter.default.addObserver(self, selector: #selector(applyPowerMode), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    func register(_ s: Spring...) { springs += s }
    func addTicker(_ t: @escaping (Double) -> Bool) { tickers.append(t); wake() }

    func wake() {
        guard let link, link.isPaused else { return }
        last = CACurrentMediaTime(); link.isPaused = false
    }

    @objc private func frame(_ l: CADisplayLink) {
        let now = l.targetTimestamp
        let dt = min(1.0 / 30, now - last); last = now
        springs.forEach { $0.step(dt) }
        tickers = tickers.filter { $0(dt) }
        CATransaction.begin(); CATransaction.setDisableActions(true)   // we own every frame; no implicit animations
        onFrame?()
        CATransaction.commit()
        if springs.allSatisfy(\.isResting) && tickers.isEmpty { l.isPaused = true }    // idle → 0 frames
    }

    @objc private func applyPowerMode() {
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        link?.preferredFrameRateRange = low ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                                            : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        Particles.budget = low ? 50 : 140
    }
}

/// 8 fps sprite clock, separate from the display link. Paused when nothing is visible.
final class SpriteClock {
    static let shared = SpriteClock()
    private var timer: Timer?
    private var views = NSHashTable<PetSpriteLayer>.weakObjects()
    var isVisible = true { didSet { update() } }

    func add(_ l: PetSpriteLayer) { views.add(l); update() }
    private func update() {
        let run = isVisible && views.count > 0 && !ScreenState.asleepOrLocked && !ScreenState.fullScreenAppActive
        if run, timer == nil {
            timer = Timer(timeInterval: 1.0 / 8, repeats: true) { [weak self] _ in self?.views.allObjects.forEach { $0.advance() } }
            timer?.tolerance = 0.02                      // let the system coalesce wakeups
            RunLoop.main.add(timer!, forMode: .common)
        } else if !run { timer?.invalidate(); timer = nil }
    }
}
