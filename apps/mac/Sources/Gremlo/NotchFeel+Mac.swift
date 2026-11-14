import AppKit
import AVFoundation
import GremloCore
import QuartzCore

// Notch feel on the Mac (docs/design/notch-feel/NOTCH_FEEL.md, swift/ reference): the frame clock, the shape layer,
// the sprite clock, rolling numbers and the sound kit. Numbers live in GremloCore (Spring, NotchFeel).

// MARK: - Frame clock (#28, #29)

/// Springs and tickers get every display frame while something moves; the link pauses the moment nothing does,
/// so a resting notch costs no frames at all. Low Power Mode caps it at 60 Hz.
final class NotchDriver: NSObject {
    static let shared = NotchDriver()

    private var link: AnyObject?      // CADisplayLink (macOS 14); a 60 Hz timer stands in on macOS 13
    private var fallback: Timer?
    private var last: CFTimeInterval = 0
    private var springs: [Spring] = []
    private var tickers: [(Double) -> Bool] = []
    var onFrame: (() -> Void)?
    /// Frames since the clock last woke, for the peak-haptic log.
    private(set) var frame = 0
    var isRunning: Bool { if #available(macOS 14.0, *), let l = link as? CADisplayLink { return !l.isPaused }; return fallback != nil }

    func attach(to view: NSView) {
        if #available(macOS 14.0, *) {
            let l = view.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            l.isPaused = true
            link = l
        }
        applyPowerMode()
        NotificationCenter.default.addObserver(self, selector: #selector(applyPowerMode), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    func register(_ s: Spring...) {
        for x in s { x.wake = { [weak self] in self?.wake() }; springs.append(x) }
    }
    func addTicker(_ t: @escaping (Double) -> Bool) { tickers.append(t); wake() }

    func wake() {
        guard !isRunning else { return }
        last = CACurrentMediaTime()
        frame = 0
        if #available(macOS 14.0, *), let l = link as? CADisplayLink { l.isPaused = false; return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.advance(to: CACurrentMediaTime()) }
        RunLoop.main.add(t, forMode: .common)
        fallback = t
    }

    @available(macOS 14.0, *)
    @objc private func tick(_ l: CADisplayLink) { advance(to: l.targetTimestamp) }

    private func advance(to now: CFTimeInterval) {
        let dt = max(0, min(1.0 / 30, now - last))
        last = now
        frame += 1
        springs.forEach { $0.step(dt) }
        tickers = tickers.filter { $0(dt) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // every frame is ours: no implicit animations
        onFrame?()
        CATransaction.commit()
        if springs.allSatisfy(\.isResting) && tickers.isEmpty { pause() }
    }

    private func pause() {
        #if DEBUG
        print("notch: clock paused after \(frame) frames")
        #endif
        if #available(macOS 14.0, *), let l = link as? CADisplayLink { l.isPaused = true }
        fallback?.invalidate()
        fallback = nil
    }

    @objc private func applyPowerMode() {
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        if #available(macOS 14.0, *), let l = link as? CADisplayLink {
            l.preferredFrameRateRange = low ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60) : CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
    }
}

// MARK: - Sprite clock (#29)

/// Pet sprites in the notch run on their own 8 fps clock, off the display link. It runs only while a sprite is on
/// screen and the display is awake and unlocked; under Reduce Motion sprites hold frame 0 and it doesn't run at all.
final class SpriteClock {
    static let shared = SpriteClock()
    private var timer: Timer?
    private let views = NSHashTable<SpriteView>.weakObjects()
    var visible = true { didSet { if visible != oldValue { update() } } }
    private var asleep = false

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        for (name, value) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
                              (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = value; self?.update() }
        }
    }

    func add(_ v: SpriteView) { views.add(v); update() }

    private func update() {
        let run = visible && !asleep && !Motion.reduce && !views.allObjects.isEmpty
        if run, timer == nil {
            let t = Timer(timeInterval: 1.0 / 8, repeats: true) { [weak self] _ in
                guard let self else { return }
                let live = self.views.allObjects
                if live.isEmpty { self.update() } else { live.forEach { $0.advance() } }
            }
            t.tolerance = 0.02  // let the system coalesce the wakeups
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !run {
            timer?.invalidate()
            timer = nil
        }
    }

    fileprivate func removed() { if views.allObjects.isEmpty { update() } }
}

/// A pet sprite row drawn in the notch, advanced by the sprite clock.
final class SpriteView: NSView {
    private let frames: [CGImage]
    private var index = 0
    var faceLeft = false { didSet { if faceLeft != oldValue { layer?.setAffineTransform(faceLeft ? CGAffineTransform(scaleX: -1, y: 1) : .identity) } } }

    init(frames: [CGImage], size: CGFloat) {
        self.frames = frames
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.contents = frames.first
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .nearest
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        if frames.count > 1 { SpriteClock.shared.add(self) }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { DispatchQueue.main.async { SpriteClock.shared.removed() } }

    func advance() {
        guard window != nil, frames.count > 1 else { return }
        index = (index + 1) % frames.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = frames[index]
        CATransaction.commit()
    }
}

// MARK: - Shape (#2, #13, #17)

/// The notch as one path with ears, rebuilt every frame from the springs: body, a live rim half hidden under it,
/// a glow in the agent's colour and a depth shadow. Path and transform only, never a window resize.
final class NotchShapeLayer: CALayer {
    let body = CAShapeLayer()
    private let glow = CAShapeLayer()
    private let rimBox = CALayer()            // masked to a 3 pt stroke of the path; never rotates
    private let rim = CAGradientLayer()       // the conic gradient inside it; this is what spins
    private let rimMask = CAShapeLayer()

    var rimColor: NSColor = .systemOrange { didSet { if rimColor != oldValue { updateRim() } } }
    var rimMode: NotchFeel.Rim = .off { didSet { if rimMode != oldValue { updateRim() } } }

    override init() {
        super.init()
        body.fillColor = NSColor.black.cgColor
        body.shadowColor = NSColor.black.cgColor
        body.shadowOpacity = 0
        body.shadowRadius = 24
        body.shadowOffset = CGSize(width: 0, height: -10)   // 10 pt down onto the desktop
        glow.fillColor = NSColor.black.cgColor
        glow.shadowRadius = 28
        glow.shadowOffset = CGSize(width: 0, height: -6)
        glow.shadowOpacity = 0
        rim.type = .conic
        rim.startPoint = CGPoint(x: 0.5, y: 0.5)
        rim.endPoint = CGPoint(x: 0.5, y: 0)
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.white.cgColor
        rimMask.lineWidth = 3
        rimBox.mask = rimMask
        rimBox.addSublayer(rim)
        rimBox.opacity = 0
        for l in [glow, rimBox, body] as [CALayer] { addSublayer(l) }
        actions = ["sublayerTransform": NSNull()]
    }
    required init?(coder: NSCoder) { fatalError() }
    override init(layer: Any) { super.init(layer: layer) }

    func apply(_ g: NotchGeometry, centerX cx: CGFloat, top: CGFloat, squash: CGFloat, press: CGFloat, open: CGFloat) {
        let path = g.path(centerX: cx, top: top)
        body.path = path; glow.path = path; rimMask.path = path
        body.shadowPath = path
        glow.shadowPath = path
        rimBox.frame = bounds
        rimMask.frame = rimBox.bounds
        let side = max(g.width, g.height) * 1.6   // a big square, so the spin never shows a corner
        rim.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        rim.position = CGPoint(x: cx, y: top - g.height / 2)
        // squash and stretch around the top centre, times the press dent
        let (sx, sy) = NotchFeel.stretch(squash: squash, press: press)
        var t = CATransform3DMakeTranslation(cx, top, 0)
        t = CATransform3DScale(t, sx, sy, 1)
        t = CATransform3DTranslate(t, -cx, -top, 0)
        sublayerTransform = t
        body.shadowOpacity = Float(0.45 * max(0, min(1, open)))
    }

    /// The Konami disco: the rim cycles through the hues for 3.6 s, then goes back to what it was.
    func disco() {
        let hues = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { NSColor(hue: $0, saturation: 0.85, brightness: 1, alpha: 1).cgColor }
        let a = CAKeyframeAnimation(keyPath: "colors")
        a.values = hues.map { [$0, $0] }
        a.duration = 3.6
        let show = CABasicAnimation(keyPath: "opacity")
        show.fromValue = 1; show.toValue = 1; show.duration = 3.6
        rim.add(a, forKey: "disco")
        rimBox.add(show, forKey: "disco")
    }

    private func updateRim() {
        rim.removeAnimation(forKey: "flow")
        glow.shadowColor = rimColor.cgColor
        switch rimMode {
        case .off:
            rimBox.opacity = 0; glow.shadowOpacity = 0
        case .solid:
            rimBox.opacity = 1; glow.shadowOpacity = 0.5
            rim.colors = [rimColor.cgColor, rimColor.cgColor]
            rim.locations = nil
        case .flow:
            rimBox.opacity = 1; glow.shadowOpacity = 0.35
            let c = rimColor.cgColor, clear = rimColor.withAlphaComponent(0).cgColor
            rim.colors = [clear, c, clear, clear, c, clear]
            rim.locations = [0, 0.3, 0.45, 0.65, 0.8, 0.95]
            guard !Motion.reduce else { return }
            let a = CABasicAnimation(keyPath: "transform.rotation.z")  // rotate the gradient, never redraw it
            a.fromValue = 0
            a.toValue = -2 * Double.pi
            a.duration = 2.2
            a.repeatCount = .infinity
            rim.add(a, forKey: "flow")
        }
    }
}

func nsColor(hex: String) -> NSColor {
    guard let c = RGB(hex: hex) else { return .systemOrange }
    return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
}

// MARK: - Rolling numbers (#18)

/// Digits roll in clipped 14 pt cells on the release spring; everything else stays put. Mono, tabular figures.
final class RollingLabel: NSView {
    private let font: NSFont
    private let cell: CGFloat = 14
    private var charW: CGFloat
    private var text = ""
    private var columns: [CALayer?] = []
    private var glyphs: [[CATextLayer]] = []
    var color: NSColor { didSet { if color != oldValue { glyphs.joined().forEach { $0.foregroundColor = color.cgColor } } } }

    init(size: CGFloat, color: NSColor) {
        font = .monospacedSystemFont(ofSize: size, weight: .medium)
        self.color = color
        charW = ceil(("0" as NSString).size(withAttributes: [.font: font]).width)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(text.count) * charW, height: cell) }

    var stringValue: String {
        get { text }
        set { set(newValue) }
    }

    private func set(_ s: String) {
        guard s != text else { return }
        let a = Array(s), b = Array(text)
        let sameShape = a.count == b.count && zip(a, b).allSatisfy { $0.isNumber == $1.isNumber && ($0.isNumber || $0 == $1) }
        guard sameShape else { rebuild(s); return }
        for (i, ch) in a.enumerated() where ch != b[i] {
            if let col = columns[i], let d = ch.wholeNumberValue { roll(col, to: d) }
        }
        text = s
    }

    private func rebuild(_ s: String) {
        text = s
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        columns = []; glyphs = []
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for (i, ch) in s.enumerated() {
            let box = CALayer()
            box.frame = CGRect(x: CGFloat(i) * charW, y: 0, width: charW, height: cell)
            box.masksToBounds = true
            layer?.addSublayer(box)
            let strings = ch.wholeNumberValue != nil ? (0...9).map(String.init) : [String(ch)]
            let col = CALayer()
            col.frame = CGRect(x: 0, y: 0, width: charW, height: cell * CGFloat(strings.count))
            let ts: [CATextLayer] = strings.enumerated().map { j, str in
                let t = CATextLayer()
                t.string = str; t.font = font; t.fontSize = font.pointSize
                t.foregroundColor = color.cgColor; t.contentsScale = scale; t.alignmentMode = .center
                t.frame = CGRect(x: 0, y: CGFloat(j) * cell - 1, width: charW, height: cell)
                col.addSublayer(t)
                return t
            }
            box.addSublayer(col)
            glyphs.append(ts)
            if let d = ch.wholeNumberValue {
                col.setAffineTransform(CGAffineTransform(translationX: 0, y: -CGFloat(d) * cell))
                columns.append(col)
            } else { columns.append(nil) }
        }
        invalidateIntrinsicContentSize()
    }

    private func roll(_ col: CALayer, to d: Int) {
        let to = -CGFloat(d) * cell
        let from = (col.presentation() ?? col).affineTransform().ty
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        col.setAffineTransform(CGAffineTransform(translationX: 0, y: to))
        CATransaction.commit()
        guard !Motion.reduce else { return }
        let p = SpringParams.release
        let a = CASpringAnimation(keyPath: "transform.translation.y")
        a.fromValue = from; a.toValue = to
        a.mass = 1; a.stiffness = p.stiffness; a.damping = p.dampingCoefficient
        a.duration = a.settlingDuration
        col.add(a, forKey: "roll")
    }
}

// MARK: - Content stagger (#3)

enum Stagger {
    /// Rows fade in 60 ms after the shape starts moving, 45 ms apart: 180 ms of opacity and a 6 pt slide up on the
    /// release spring. Core Animation runs it, so it costs the frame clock nothing.
    static func rows(_ views: [NSView]) {
        guard !Motion.reduce else { return }
        let now = CACurrentMediaTime(), p = SpringParams.release
        for (i, v) in views.enumerated() {
            v.wantsLayer = true
            guard let l = v.layer else { continue }
            let begin = now + NotchFeel.rowDelay(i, reduce: false)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            fade.duration = NotchFeel.rowFade
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.beginTime = begin; fade.fillMode = .backwards
            let slide = CASpringAnimation(keyPath: "transform.translation.y")
            slide.fromValue = -NotchFeel.rowSlide; slide.toValue = 0
            slide.mass = 1; slide.stiffness = p.stiffness; slide.damping = p.dampingCoefficient
            slide.duration = slide.settlingDuration
            slide.beginTime = begin; slide.fillMode = .backwards
            l.add(fade, forKey: "stagger.fade")
            l.add(slide, forKey: "stagger.slide")
        }
    }
}

// MARK: - Sound kit (#22)

/// Notch sounds through AVAudioEngine with preloaded buffers and a 6-voice pool, so a sound starts within a few ms
/// and overlapping ones never cut each other. Off, Subtle (default, quiet) or Full. Silent during a screen share,
/// a meeting, Focus or full-screen video, and never for a sponsored line. The engine stops after 20 s of silence.
final class SoundKit {
    static let shared = SoundKit()
    enum Level: Int, CaseIterable { case off, subtle, full
        var volume: Float { [0, 0.12, 0.5][rawValue] }
        var title: String { ["Off", "Subtle", "Full"][rawValue] }
    }
    enum Sound: String, CaseIterable { case pop, close, tick, chomp, whoosh, shutter, chime, thud, boing, fail }
    static let files: [Sound: String] = [.pop: "door-open", .close: "door-close", .tick: "tick", .chomp: "meal", .whoosh: "whoosh",
                                         .shutter: "shutter", .chime: "celebrate", .thud: "thud", .boing: "boing", .fail: "fail"]
    /// How much of each file to keep. The pet recordings have long tails; the notch only wants the attack.
    private static let keep: [Sound: Double] = [.pop: 0.12, .chomp: 0.20, .chime: 0.36, .boing: 0.16, .fail: 0.20, .whoosh: 0.16]
    /// Tick is a 20 ms click, so it sits a little hotter than the longer hits or Subtle swallows it.
    private static let gain: [Sound: Float] = [.pop: 0.8, .close: 0.9, .tick: 1.35, .chomp: 0.75, .whoosh: 0.85,
                                               .shutter: 1, .chime: 0.6, .thud: 0.9, .boing: 0.55, .fail: 0.7]

    var level = Level(rawValue: defaults.object(forKey: "notchSound") as? Int ?? Level.subtle.rawValue) ?? .subtle {
        didSet { defaults.set(level.rawValue, forKey: "notchSound"); engine?.mainMixerNode.outputVolume = level.volume }
    }
    private var engine: AVAudioEngine?
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var idle: Timer?

    /// Built on first use, so a Mac that never hears a notch sound never starts the audio engine.
    private func prepare() -> AVAudioEngine? {
        if let engine { return engine }
        for s in Sound.allCases {
            let url = assetsDir.appendingPathComponent("sounds/\(Self.files[s] ?? s.rawValue).wav")
            guard let f = try? AVAudioFile(forReading: url),
                  let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { continue }
            try? f.read(into: b)
            buffers[s] = Self.shaped(b, keep: Self.keep[s])
        }
        // The notch and the door get their own clicks, in the same format as the kit so the engine can play them.
        let kit = buffers.values.first?.format
        if let pop = Self.blip(freq: 620, seconds: 0.07, noise: 0.35, format: kit) { buffers[.pop] = pop }
        if let close = Self.blip(freq: 360, seconds: 0.08, noise: 0.12, format: kit) { buffers[.close] = close }
        guard let fmt = buffers.values.first?.format else { return nil }
        let e = AVAudioEngine()
        for _ in 0..<6 {
            let p = AVAudioPlayerNode()
            e.attach(p)
            e.connect(p, to: e.mainMixerNode, format: fmt)
            players.append(p)
        }
        e.mainMixerNode.outputVolume = level.volume
        e.prepare()
        engine = e
        return e
    }

    /// Starts the engine before the first gesture, so the first tick isn't waiting on file reads.
    func warm() {
        guard level != .off, let e = prepare(), !e.isRunning else { return }
        try? e.start()
        armIdle()
    }

    func play(_ s: Sound) {
        guard level != .off, !silence.silent, let e = prepare(), let b = buffers[s] else { return }
        if !e.isRunning { do { try e.start() } catch { return } }
        let p = players.first { !$0.isPlaying } ?? players[next]
        next = (next + 1) % players.count
        if p.isPlaying { p.stop() }   // only when every voice is busy; a free voice is never cut
        p.volume = Self.gain[s] ?? 1
        p.scheduleBuffer(b, at: nil)
        p.play()
        armIdle()
    }

    private func armIdle() {
        idle?.invalidate()
        idle = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.engine?.pause() }
        idle?.tolerance = 2
    }

    /// Keeps the attack and fades the last 8 ms, so a trimmed file doesn't click at the cut.
    private static func shaped(_ b: AVAudioPCMBuffer, keep: Double?) -> AVAudioPCMBuffer {
        guard let keep, let src = b.floatChannelData else { return b }
        let rate = b.format.sampleRate
        let frames = AVAudioFrameCount(min(Double(b.frameLength), keep * rate))
        guard frames > 0, frames < b.frameLength, let out = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: frames) else { return b }
        out.frameLength = frames
        let n = Int(frames)
        let fade = min(n, Int(0.008 * rate))
        for c in 0..<Int(b.format.channelCount) {
            let from = src[c]
            let to = out.floatChannelData![c]
            for i in 0..<n { to[i] = from[i] }
            if fade > 1 {
                for i in 0..<fade {
                    to[n - fade + i] *= Float(fade - i) / Float(fade)
                }
            }
        }
        return out
    }

    /// A short click: a falling sine plus a few milliseconds of noise. One buffer, built once.
    private static func blip(freq: Double, seconds: Double, noise: Double, format: AVAudioFormat?) -> AVAudioPCMBuffer? {
        let fmt = format ?? AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        guard let fmt else { return nil }
        let n = Int(seconds * fmt.sampleRate)
        guard n > 0, let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        b.frameLength = AVAudioFrameCount(n)
        var seed: UInt32 = 0x6d2b79f5
        func sample(_ i: Int) -> Double {
            seed = seed &* 1664525 &+ 1013904223
            let white = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            let t = Double(i) / fmt.sampleRate
            let env = exp(-t * 36)
            let grit = i < 120 ? white * noise * exp(-Double(i) / 22) : 0
            return (sin(2 * .pi * freq * t) * 0.62 + grit) * env
        }
        if let ch = b.floatChannelData {
            for c in 0..<Int(fmt.channelCount) { for i in 0..<n { ch[c][i] = Float(sample(i)) } }
        } else if let ch = b.int16ChannelData {
            for c in 0..<Int(fmt.channelCount) { for i in 0..<n { ch[c][i] = Int16(max(-1, min(1, sample(i))) * 32767) } }
        }
        return b
    }
}

// MARK: - Particles (#14)

/// CAEmitterLayer bursts from the notch's bottom edge: the render server animates them, so the frame clock stays idle.
/// Unflipped coordinates: down is -y, so gravity is a negative yAcceleration.
enum Particles {
    static func burst(_ k: NotchFeel.Burst, in root: CALayer, at p: CGPoint, width: CGFloat, count n: Int, palette: [NSColor]) {
        let e = CAEmitterLayer()
        e.emitterShape = .line
        e.emitterMode = .points
        e.emitterPosition = p
        e.emitterSize = CGSize(width: width, height: 1)
        e.emitterCells = cells(k, palette: palette)
        e.beginTime = CACurrentMediaTime()
        // each cell's rate x the 120 ms burst adds up to about n particles in all
        let total = (e.emitterCells ?? []).reduce(Float(0)) { $0 + $1.birthRate }
        if total > 0 { let scale = Float(n) / (total * 0.12); e.emitterCells?.forEach { $0.birthRate *= scale } }
        root.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { e.birthRate = 0 }  // a burst, not a fountain
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { e.removeFromSuperlayer() }
    }

    private static func cells(_ k: NotchFeel.Burst, palette: [NSColor]) -> [CAEmitterCell] {
        switch k {
        case .confetti:
            return palette.map { color in
                let c = CAEmitterCell()
                c.contents = rect(8, 4); c.color = color.cgColor
                c.birthRate = 70; c.lifetime = 2.2; c.velocity = 220; c.velocityRange = 120
                c.emissionLongitude = -.pi / 2; c.emissionRange = .pi * 0.9; c.yAcceleration = -520
                c.spin = 4; c.spinRange = 8; c.scaleRange = 0.4; c.alphaSpeed = -0.4
                return c
            }
        case .sparks:
            let c = CAEmitterCell()
            c.contents = rect(10, 2); c.color = NSColor(srgbRed: 0.91, green: 0.84, blue: 1, alpha: 1).cgColor
            c.birthRate = 300; c.lifetime = 0.7; c.velocity = 320; c.velocityRange = 160
            c.emissionLongitude = -.pi / 2; c.emissionRange = .pi; c.yAcceleration = -300; c.alphaSpeed = -1.4
            return [c]
        case .smoke:
            let c = CAEmitterCell()
            c.contents = dot(24); c.color = NSColor(white: 0.65, alpha: 0.35).cgColor
            c.birthRate = 110; c.lifetime = 1.6; c.velocity = 30; c.velocityRange = 20
            c.emissionLongitude = -.pi / 2; c.yAcceleration = 20  // it rises
            c.scale = 0.5; c.scaleSpeed = 0.6; c.alphaSpeed = -0.25
            return [c]
        case .sweat:
            let c = CAEmitterCell()
            c.contents = dot(6); c.color = NSColor(srgbRed: 0.49, green: 0.78, blue: 1, alpha: 1).cgColor
            c.birthRate = 50; c.lifetime = 0.9; c.velocity = 60; c.emissionRange = .pi / 3
            c.emissionLongitude = -.pi / 2; c.yAcceleration = -600
            return [c]
        }
    }

    private static var images: [String: CGImage] = [:]
    private static func image(_ key: String, _ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        if let i = images[key] { return i }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        draw(ctx)
        let i = ctx.makeImage()
        images[key] = i
        return i
    }
    static func rect(_ w: Int, _ h: Int) -> CGImage? { image("r\(w)x\(h)", w, h) { $0.fill(CGRect(x: 0, y: 0, width: w, height: h)) } }
    static func dot(_ d: Int) -> CGImage? { image("d\(d)", d, d) { $0.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d)) } }
}

extension NotchShapeLayer {
    /// A pulse of the glow: the visible half of the approval heartbeat.
    func beat() {
        guard let glow = sublayers?.first as? CAShapeLayer else { return }
        let a = CABasicAnimation(keyPath: "shadowOpacity")
        a.fromValue = 0.95
        a.toValue = glow.shadowOpacity
        a.duration = 0.4
        glow.add(a, forKey: "beat")
    }
}
