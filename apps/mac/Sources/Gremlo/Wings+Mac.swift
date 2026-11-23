import AppKit
import GremloCore

/// Two slim strips, one on each side of the notch housing, while an agent runs (Wings.mode decides when). Working is a
/// highlight sweeping toward the notch with no fraction shown; done fills the strips green and glows once; failed
/// fills them red. Reduce Motion: a steady dim strip, no sweep and no glow animation.
final class WingsLayer: CALayer {
    private static let wingW: CGFloat = 56, wingH: CGFloat = 3, gap: CGFloat = 8
    private let left = Wing(toward: 1), right = Wing(toward: -1)
    private(set) var mode: WingsMode = .off
    var agentColor: NSColor = .systemOrange

    override init() {
        super.init()
        for w in [left, right] { addSublayer(w) }
        opacity = 1
    }
    required init?(coder: NSCoder) { fatalError() }
    override init(layer: Any) { super.init(layer: layer) }

    /// Called every frame with the housing's width and the panel's top; the strips ride its edges, centred in the menu bar row.
    func layout(centerX cx: CGFloat, housingWidth: CGFloat, top: CGFloat, band: CGFloat) {
        let y = top - band / 2 - Self.wingH / 2
        let size = CGSize(width: Self.wingW, height: Self.wingH)
        left.frame = CGRect(origin: CGPoint(x: cx - housingWidth / 2 - Self.gap - Self.wingW, y: y), size: size)
        right.frame = CGRect(origin: CGPoint(x: cx + housingWidth / 2 + Self.gap, y: y), size: size)
        let fits = housingWidth <= CGFloat(Wings.maxHousingWidth)
        isHidden = !fits   // off is each strip's own opacity, so it fades out instead of cutting
    }

    func set(_ new: WingsMode, reduceMotion: Bool) {
        guard new != mode else { return }
        mode = new
        for w in [left, right] { w.show(new, agent: agentColor, reduceMotion: reduceMotion) }
    }
}

private final class Wing: CALayer {
    private let clip = CALayer()
    private let fill = CAGradientLayer()
    private let toward: CGFloat   // +1 sweeps to the right (the left strip), -1 to the left

    init(toward: CGFloat) {
        self.toward = toward
        super.init()
        backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor
        cornerRadius = 1.5
        shadowOffset = .zero
        shadowRadius = 8
        shadowOpacity = 0
        clip.masksToBounds = true
        clip.cornerRadius = 1.5
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        clip.addSublayer(fill)
        addSublayer(clip)
        opacity = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    override init(layer: Any) { toward = 1; super.init(layer: layer) }

    override func layoutSublayers() {
        super.layoutSublayers()
        clip.frame = bounds
    }

    func show(_ mode: WingsMode, agent: NSColor, reduceMotion: Bool) {
        fill.removeAllAnimations()
        removeAnimation(forKey: "glow")
        shadowOpacity = 0
        let w = bounds.width
        switch mode {
        case .off:
            fade(to: 0)
        case .working:
            let c = agent.cgColor, clear = agent.withAlphaComponent(0).cgColor
            fade(to: 1)
            if reduceMotion {
                fill.colors = [agent.withAlphaComponent(0.5).cgColor, agent.withAlphaComponent(0.5).cgColor]
                fill.frame = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            } else {
                fill.colors = [clear, c, clear]
                fill.frame = CGRect(x: -24, y: 0, width: 24, height: bounds.height)
                let a = CABasicAnimation(keyPath: "position.x")
                let start: CGFloat = toward > 0 ? -12 : w + 12, end: CGFloat = toward > 0 ? w + 12 : -12
                a.fromValue = start; a.toValue = end
                a.duration = 1.3
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                fill.add(a, forKey: "sweep")
            }
        case .done, .failed:
            let c = nsColor(hex: mode == .done ? NotchFeel.doneColor : NotchFeel.failColor)
            fade(to: 1)
            fill.colors = [c.cgColor, c.cgColor]
            fill.frame = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            shadowColor = c.cgColor
            if mode == .done, !reduceMotion {  // one glow, in and out; failure gets no celebration
                let g = CAKeyframeAnimation(keyPath: "shadowOpacity")
                g.values = [0, 0.95, 0]
                g.keyTimes = [0, 0.3, 1]
                g.duration = Wings.finishHold
                add(g, forKey: "glow")
            }
        }
    }

    private func fade(to v: Float) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = presentation()?.opacity ?? opacity
        a.toValue = v
        a.duration = 0.2
        opacity = v
        add(a, forKey: "fade")
    }
}
