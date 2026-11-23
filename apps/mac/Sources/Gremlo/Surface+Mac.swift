import AppKit

/// One treatment for everything Gremlo floats over the desktop: a glass fill, a 1 pt edge highlight, a soft shadow and
/// an optional glow. The notch, the approval card inside it, the menu bar popover and the sign all read these numbers,
/// so changing the look is a change here. Reverting a surface to its old look is deleting its `Surface` call.
enum Surface {
    struct Style {
        var edge: CGFloat                 // alpha of the 1 pt highlight
        var shadow: (opacity: Float, radius: CGFloat, dy: CGFloat)?   // nil: the panel uses the window's own soft shadow
        var glow: (radius: CGFloat, dy: CGFloat)?
        var glassAlpha: CGFloat           // how much of the surface colour sits over the blur (1 = opaque)
    }

    /// Black has to stay black here: it joins the hardware notch. So no glass, and the edge fades in from the top.
    static let notch = Style(edge: 0.16, shadow: (0.45, 24, -10), glow: (28, -6), glassAlpha: 1)
    static let popover = Style(edge: 0.12, shadow: nil, glow: nil, glassAlpha: 0.9)
    static let sign = Style(edge: 0, shadow: nil, glow: nil, glassAlpha: 1)   // pixel art keeps its own outline; it only gets the shadow

    /// The 1 pt highlight around `path`, brightest at the bottom edge and fading out toward the top so it never draws
    /// a line along the bezel. Add it above the body; call `updateEdge` whenever the path or bounds change.
    static func edgeLayer(_ s: Style) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.fillColor = nil
        l.strokeColor = NSColor.white.withAlphaComponent(s.edge).cgColor
        l.lineWidth = 1
        let fade = CAGradientLayer()
        fade.colors = [NSColor.clear.cgColor, NSColor.white.cgColor]
        fade.startPoint = CGPoint(x: 0.5, y: 1)   // layer space is y-up: 1 is the top
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        l.mask = fade
        return l
    }

    static func updateEdge(_ l: CAShapeLayer, path: CGPath, box: CGRect) {
        l.path = path
        l.frame = l.superlayer?.bounds ?? l.frame
        l.mask?.frame = box
    }

    static func applyShadow(_ l: CALayer, _ s: Style, strength: CGFloat = 1) {
        guard let sh = s.shadow else { return }
        l.shadowColor = NSColor.black.cgColor
        l.shadowOpacity = Float(CGFloat(sh.opacity) * max(0, min(1, strength)))
        l.shadowRadius = sh.radius
        l.shadowOffset = CGSize(width: 0, height: sh.dy)
    }

    /// A glass backing for a panel surface: a blur under the tinted fill, clipped to the surface's corners.
    static func glass(under surface: NSView, _ s: Style) {
        guard s.glassAlpha < 1 else { return }
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.frame = surface.bounds
        blur.autoresizingMask = [.width, .height]
        surface.addSubview(blur, positioned: .below, relativeTo: nil)
    }

    /// A 1 pt inner line for view-backed surfaces (the popover): light on dark, dark on light.
    static let edgeColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white.withAlphaComponent(popover.edge) : NSColor.black.withAlphaComponent(popover.edge * 0.7) }
}
