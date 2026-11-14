// Particles.swift · confetti, sparks, smoke, sweat (idea 14). Reference code, not compiled here.
// CAEmitterLayer bursts from the notch's bottom corners. GPU-driven, capped, off under Reduce Motion.

import AppKit
import QuartzCore

final class Particles {
    static let shared = Particles()
    static var budget = 140                      // NotchDriver halves it in Low Power Mode

    func react(to m: NotchMode, from notch: NotchLayer) {
        guard !Motion.reduce else { return }
        switch m {
        case .done:    burst(.confetti, on: notch)
        case .merge:   burst(.sparks, on: notch)
        case .fail:    burst(.smoke, on: notch)
        case .battery: burst(.sweat, on: notch)
        default: break
        }
    }

    enum Kind { case confetti, sparks, smoke, sweat }

    func burst(_ k: Kind, on notch: NotchLayer) {
        let e = CAEmitterLayer()
        let f = notch.body.path?.boundingBox ?? notch.bounds
        e.emitterShape = .line; e.emitterMode = .points
        e.emitterPosition = CGPoint(x: f.midX, y: f.maxY - 4); e.emitterSize = CGSize(width: f.width - 12, height: 1)
        e.emitterCells = cells(k)
        e.beginTime = CACurrentMediaTime()
        notch.superlayer?.addSublayer(e)          // the overlay window's root layer, so particles can leave the notch
        let n = Float(min(Particles.budget, k == .confetti ? 60 : k == .sparks ? 36 : k == .smoke ? 14 : 6))
        e.birthRate = 1
        e.cells(scaledTo: n)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { e.birthRate = 0 }                // a burst, not a fountain
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { e.removeFromSuperlayer() }
    }

    private func cells(_ k: Kind) -> [CAEmitterCell] {
        switch k {
        case .confetti:
            return Palette.pets.map { color in
                let c = CAEmitterCell(); c.contents = Sprites.rect(8, 4); c.color = color.cgColor
                c.birthRate = 70; c.lifetime = 2.2; c.velocity = 220; c.velocityRange = 120
                c.emissionLongitude = .pi / 2; c.emissionRange = .pi * 0.9; c.yAcceleration = 520
                c.spin = 4; c.spinRange = 8; c.scaleRange = 0.4; c.alphaSpeed = -0.4
                return c
            }
        case .sparks:
            let c = CAEmitterCell(); c.contents = Sprites.rect(10, 2); c.color = NSColor(srgbRed: 0.91, green: 0.84, blue: 1, alpha: 1).cgColor
            c.birthRate = 300; c.lifetime = 0.7; c.velocity = 320; c.velocityRange = 160; c.emissionLongitude = .pi / 2; c.emissionRange = .pi
            c.yAcceleration = 300; c.alphaSpeed = -1.4
            return [c]
        case .smoke:
            let c = CAEmitterCell(); c.contents = Sprites.softDot(24); c.color = NSColor(white: 0.65, alpha: 0.35).cgColor
            c.birthRate = 110; c.lifetime = 1.6; c.velocity = 30; c.velocityRange = 20; c.emissionLongitude = .pi / 2
            c.yAcceleration = -20; c.scale = 0.5; c.scaleSpeed = 0.6; c.alphaSpeed = -0.25
            return [c]
        case .sweat:
            let c = CAEmitterCell(); c.contents = Sprites.drop(); c.color = NSColor(srgbRed: 0.49, green: 0.78, blue: 1, alpha: 1).cgColor
            c.birthRate = 50; c.lifetime = 0.9; c.velocity = 60; c.emissionRange = .pi / 3; c.emissionLongitude = .pi / 2; c.yAcceleration = 600
            return [c]
        }
    }
}

private extension CAEmitterLayer {
    /// Each cell's birthRate × burst length ≈ n particles in total.
    func cells(scaledTo n: Float) {
        let total = (emitterCells ?? []).reduce(0) { $0 + $1.birthRate }
        guard total > 0 else { return }
        let k = n / (total * 0.12)
        emitterCells?.forEach { $0.birthRate *= k }
    }
}
