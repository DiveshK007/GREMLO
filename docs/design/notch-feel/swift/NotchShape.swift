// NotchShape.swift · the notch as a morphing path, with ears, squash/stretch, rim glow. Reference code.
//
// Draw the notch as one CAShapeLayer path rebuilt each frame from spring values. Never resize a view with
// Auto Layout during the animation: path + transform only, which stays on the GPU.

import AppKit
import QuartzCore

struct NotchGeometry {
    var width: CGFloat, height: CGFloat, radius: CGFloat
    var ear: CGFloat = 10            // the inverted corners where the notch meets the bezel
    var bulge: CGFloat = 0           // 0…1: sides bow outward while opening (squash & stretch)

    /// Top edge at y = 0 in a flipped layer.
    func path(centerX cx: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let l = cx - width / 2, r = cx + width / 2, h = height, rad = min(radius, h / 2, width / 4)
        let bow = bulge * min(10, width * 0.02)
        p.move(to: CGPoint(x: l - ear, y: 0))
        p.addQuadCurve(to: CGPoint(x: l, y: ear), control: CGPoint(x: l, y: 0))                    // left ear
        p.addCurve(to: CGPoint(x: l, y: h - rad), control1: CGPoint(x: l - bow, y: h * 0.35), control2: CGPoint(x: l - bow, y: h * 0.7))
        p.addQuadCurve(to: CGPoint(x: l + rad, y: h), control: CGPoint(x: l, y: h))                // bottom-left
        p.addLine(to: CGPoint(x: r - rad, y: h))
        p.addQuadCurve(to: CGPoint(x: r, y: h - rad), control: CGPoint(x: r, y: h))                // bottom-right
        p.addCurve(to: CGPoint(x: r, y: ear), control1: CGPoint(x: r + bow, y: h * 0.7), control2: CGPoint(x: r + bow, y: h * 0.35))
        p.addQuadCurve(to: CGPoint(x: r + ear, y: 0), control: CGPoint(x: r, y: 0))                // right ear
        p.closeSubpath()
        return p
    }
}

final class NotchLayer: CALayer {
    let body = CAShapeLayer()          // the black notch
    let rimBox = CALayer()             // masked to a 3 pt stroke of the notch path; never rotates
    let rim = CAGradientLayer()        // conic gradient inside rimBox; this is what spins
    private let rimMask = CAShapeLayer()
    let content = CALayer()            // rows, pet, buttons: masked by the body path

    var agentColor: NSColor = .systemOrange { didSet { updateRim() } }
    var rimMode: RimMode = .off { didSet { updateRim() } }
    enum RimMode { case off, solid, flow }

    override init() {
        super.init()
        isGeometryFlipped = true
        body.fillColor = NSColor.black.cgColor
        rim.type = .conic; rim.startPoint = CGPoint(x: 0.5, y: 0); rim.endPoint = CGPoint(x: 0.5, y: 1)
        rimMask.fillColor = nil; rimMask.strokeColor = NSColor.white.cgColor; rimMask.lineWidth = 3
        rimBox.mask = rimMask; rimBox.addSublayer(rim)
        let contentMask = CAShapeLayer(); content.mask = contentMask
        addSublayer(rimBox); addSublayer(body); addSublayer(content)
        body.shadowColor = NSColor.black.cgColor; body.shadowOpacity = 0; body.shadowRadius = 24; body.shadowOffset = CGSize(width: 0, height: 10)
    }
    required init?(coder: NSCoder) { fatalError() }
    override init(layer: Any) { super.init(layer: layer) }

    /// Called from NotchDriver.onFrame with the current spring values.
    func apply(_ g: NotchGeometry, lean: CGFloat, squash: CGFloat, press: CGFloat, expanded: CGFloat) {
        let cx = bounds.midX + lean
        let path = g.path(centerX: cx)
        body.path = path; rimMask.path = path; (content.mask as? CAShapeLayer)?.path = path
        rimBox.frame = bounds
        let side = max(g.width, g.height) * 1.6                       // big square so the spin never shows a corner
        rim.bounds = CGRect(x: 0, y: 0, width: side, height: side); rim.position = CGPoint(x: cx, y: g.height / 2)
        // squash & stretch around the top centre, plus the press dent
        let sx = (1 - squash * 0.03) * press, sy = (1 + squash * 0.03) * press
        var t = CATransform3DMakeTranslation(cx, 0, 0)
        t = CATransform3DScale(t, sx, sy, 1)
        t = CATransform3DTranslate(t, -cx, 0, 0)
        sublayerTransform = t
        // depth: shadow on the desktop grows with how open it is (#17)
        body.shadowOpacity = Float(0.45 * expanded)
        body.shadowPath = path
    }

    private func updateRim() {
        rim.removeAnimation(forKey: "flow")
        switch rimMode {
        case .off: rimBox.opacity = 0
        case .solid:
            rimBox.opacity = 1; rim.colors = [agentColor.cgColor, agentColor.cgColor]
        case .flow:
            rimBox.opacity = 1
            let c = agentColor.cgColor, clear = agentColor.withAlphaComponent(0).cgColor
            rim.colors = [clear, c, clear, clear, c, clear]; rim.locations = [0, 0.3, 0.45, 0.65, 0.8, 0.95]
            guard !Motion.reduce else { return }
            let a = CABasicAnimation(keyPath: "transform.rotation.z")    // cheap: rotate the gradient, not redraw it
            a.fromValue = 0; a.toValue = 2 * Double.pi; a.duration = 2.2; a.repeatCount = .infinity
            rim.add(a, forKey: "flow")
        }
    }
}

/// Agent rim colours: colour only, never a logo.
enum AgentTint {
    static func color(for agent: String) -> NSColor {
        switch agent {
        case "claude": return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)   // #D97757
        case "codex":  return NSColor(srgbRed: 0.06, green: 0.64, blue: 0.50, alpha: 1)   // #10A37F
        case "cursor": return NSColor(srgbRed: 0.30, green: 0.55, blue: 1.00, alpha: 1)   // #4C8DFF
        default:       return NSColor(srgbRed: 1.00, green: 0.35, blue: 0.24, alpha: 1)   // Gremlo #FF5A3C
        }
    }
}
