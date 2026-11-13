import AppKit
import GremloCore

// The menu bar panel and Settings, drawn from the 1.0 tokens (spec D §1, R2 §7): ink and paper, the active pet lends
// the only colour, radius 14 on surfaces and 6 on controls, mono for labels and IDs. Colours are dynamic, so a theme
// switch (System · Light · Dark) restyles everything without a rebuild.

enum UI {
    private static func hex(_ h: String, _ a: CGFloat = 1) -> NSColor {
        let c = RGB(hex: h)!
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: a)
    }
    private static func dyn(_ dark: NSColor, _ light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static let bg = dyn(hex(Palette.ink), hex(Palette.paper))
    static let surface = dyn(hex(Palette.carbon), hex(Palette.bone))
    static let control = dyn(hex(Palette.graphite), hex(Palette.ink, 0.06))
    static let controlHover = dyn(hex("#2A2A2A"), hex(Palette.ink, 0.1))
    static let fg = dyn(hex(Palette.paper), hex(Palette.ink))
    static let text = dyn(hex(Palette.paper, 0.85), hex(Palette.ink, 0.85))
    static let text2 = dyn(hex(Palette.paper, 0.62), hex(Palette.ink, 0.62))
    static let text3 = dyn(hex(Palette.paper, 0.45), hex(Palette.ink, 0.45))
    static let rule = dyn(hex(Palette.paper, 0.14), hex(Palette.ink, 0.14))
    static let ink = hex(Palette.ink), paper = hex(Palette.paper)
    static let amber = NSColor.systemOrange

    /// The pet's colour for fills (switches, bars, the primary button) and its text shade (the paper-safe one on light).
    private(set) static var accent = hex("#FF5A3C")
    private(set) static var accentText = dyn(hex("#FF5A3C"), hex("#C1442D"))
    static func setAccent(_ s: Species?) {
        guard let s else { return }
        accent = hex(s.accent)
        accentText = dyn(hex(s.accent), hex(s.paperSafe))
    }

    static func display(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .heavy, width: .compressed) }
    static func body(_ size: CGFloat = 13, _ w: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size, weight: w) }
    static func mono(_ size: CGFloat = 11, _ w: NSFont.Weight = .medium) -> NSFont { .monospacedSystemFont(ofSize: size, weight: w) }
    static func digits(_ size: CGFloat, _ w: NSFont.Weight = .semibold) -> NSFont { .monospacedDigitSystemFont(ofSize: size, weight: w) }

    // MARK: Text

    static func label(_ s: String, _ font: NSFont = body(), _ color: NSColor = text, wrap: Bool = true, width: CGFloat? = nil) -> NSTextField {
        let l = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
        l.font = font
        l.textColor = color
        if let width { l.preferredMaxLayoutWidth = width }
        if !wrap { l.lineBreakMode = .byTruncatingTail }
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }
    /// Mono, uppercase, tracked: section labels and keys (D §1 Type).
    static func caption(_ s: String, _ color: NSColor = text3) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.attributedStringValue = NSAttributedString(string: s.uppercased(), attributes: [.font: mono(10), .kern: 0.9, .foregroundColor: color])
        return l
    }

    // MARK: Layout

    static func vstack(_ v: [NSView], spacing: CGFloat = 8, insets: NSEdgeInsets = NSEdgeInsetsZero) -> NSStackView {
        let s = NSStackView(views: v)
        s.orientation = .vertical; s.alignment = .leading; s.spacing = spacing; s.edgeInsets = insets
        return s
    }
    static func hstack(_ v: [NSView], spacing: CGFloat = 8, align: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
        let s = NSStackView(views: v)
        s.orientation = .horizontal; s.alignment = align; s.spacing = spacing
        return s
    }
    static func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.init(1), for: .horizontal); return v }
    @discardableResult static func fixed(_ v: NSView, w: CGFloat? = nil, h: CGFloat? = nil) -> NSView {
        v.translatesAutoresizingMaskIntoConstraints = false
        if let w { v.widthAnchor.constraint(equalToConstant: w).isActive = true }
        if let h { v.heightAnchor.constraint(equalToConstant: h).isActive = true }
        return v
    }
    static func ruleLine(_ w: CGFloat) -> NSView { fixed(Box(fill: rule), w: w, h: 1) }

    /// A setting: title and an optional detail on the left, its control on the right.
    static func row(_ title: String, _ detail: String? = nil, _ control: NSView? = nil, width: CGFloat) -> NSView {
        let room = width - 40 - (control?.fittingSize.width ?? 0)  // the detail wraps beside the control, never under it
        let words = vstack([label(title, body(13, .medium), fg, wrap: false)] + (detail.map { [label($0, body(11), text2, width: room)] } ?? []), spacing: 2)
        let r = hstack([words, spacer()] + (control.map { [$0] } ?? []), spacing: 12)
        r.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        r.widthAnchor.constraint(equalToConstant: width).isActive = true
        r.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return r
    }
    /// A key and a value on one line; values are mono digits (amounts, counts, IDs).
    static func kv(_ key: String, _ value: String, width: CGFloat, valueColor: NSColor = fg) -> NSView {
        let v = label(value, digits(12, .medium), valueColor, wrap: false)
        v.alignment = .right
        let r = hstack([label(key, body(12), text2, wrap: false), spacer(), v], align: .firstBaseline)
        r.edgeInsets = NSEdgeInsets(top: 9, left: 14, bottom: 9, right: 14)
        r.widthAnchor.constraint(equalToConstant: width).isActive = true
        return r
    }
    /// Rows on one surface, split by hairlines; a caption above and a note below.
    static func group(_ title: String?, _ rows: [NSView], note: String? = nil, width: CGFloat) -> NSView {
        var inner: [NSView] = []
        for (i, r) in rows.enumerated() {
            if i > 0 { inner.append(ruleLine(width - 28)) }
            inner.append(r)
        }
        let list = vstack(inner, spacing: 0)
        list.alignment = .centerX
        let card = Box(fill: surface, radius: 14)
        card.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(list)
        NSLayoutConstraint.activate([list.topAnchor.constraint(equalTo: card.topAnchor), list.bottomAnchor.constraint(equalTo: card.bottomAnchor),
                                     list.leadingAnchor.constraint(equalTo: card.leadingAnchor), list.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                                     card.widthAnchor.constraint(equalToConstant: width)])
        var parts: [NSView] = []
        if let title { let c = caption(title); parts.append(padLeft(c, 14)) }
        parts.append(card)
        if let note { parts.append(padLeft(label(note, body(11), text3, width: width - 28), 14)) }
        return vstack(parts, spacing: 8)
    }
    static func padLeft(_ v: NSView, _ x: CGFloat) -> NSView {
        let s = hstack([v]); s.edgeInsets = NSEdgeInsets(top: 0, left: x, bottom: 0, right: x); return s
    }
    /// A short status line with the one square of colour in front (accent, amber or quiet).
    static func notice(_ s: String, _ tone: NSColor, width: CGFloat) -> NSView {
        let dot = fixed(Box(fill: tone, radius: 2), w: 8, h: 8)
        return hstack([dot, label(s, body(12, .medium), text, width: width - 20)], spacing: 8, align: .firstBaseline)
    }
    /// A balance tile: label, a big mono number, a thin bar in the pet's colour.
    static func stat(_ title: String, _ value: String, fraction: CGFloat?, width: CGFloat) -> NSView {
        let parts: [NSView] = [caption(title), label(value, digits(20), fg, wrap: false)] + (fraction.map { [bar($0, width: width - 24)] } ?? [])
        let s = vstack(parts, spacing: 6, insets: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        return wrap(s, fill: control, radius: 10, width: width)
    }
    static func bar(_ fraction: CGFloat, width: CGFloat) -> NSView {
        let track = Box(fill: rule, radius: 1.5)
        let fill = Box(fill: accent, radius: 1.5)
        track.addSubview(fill)
        fill.frame = NSRect(x: 0, y: 0, width: width * min(max(fraction, 0), 1), height: 3)
        return fixed(track, w: width, h: 3)
    }
    static func wrap(_ v: NSView, fill: NSColor, radius: CGFloat, width: CGFloat? = nil, stroke: NSColor? = nil) -> NSView {
        let b = Box(fill: fill, radius: radius, stroke: stroke)
        b.translatesAutoresizingMaskIntoConstraints = false
        v.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: b.topAnchor), v.bottomAnchor.constraint(equalTo: b.bottomAnchor),
                                     v.leadingAnchor.constraint(equalTo: b.leadingAnchor), v.trailingAnchor.constraint(equalTo: b.trailingAnchor)])
        if let width { b.widthAnchor.constraint(equalToConstant: width).isActive = true }
        return b
    }
    /// The sponsored line as the pet holds it: paper face, ink frame, the AD tab (R2 §2). Never truncated.
    static func plate(_ line: String, width: CGFloat) -> NSView {
        let text = label(line, body(13, .semibold), ink, width: width - 60)
        let ad = NSTextField(labelWithString: "AD")
        ad.font = mono(9); ad.textColor = ink
        let tag = wrap(padded(ad, 2, 4), fill: paper, radius: 2, stroke: ink)
        let r = hstack([text, spacer(), tag], spacing: 8, align: .top)
        r.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 8)
        let b = wrap(r, fill: paper, radius: 4, width: width, stroke: ink)
        b.setAccessibilityLabel("Sponsored: \(line)")
        return b
    }
    static func padded(_ v: NSView, _ y: CGFloat, _ x: CGFloat) -> NSView {
        let s = hstack([v]); s.edgeInsets = NSEdgeInsets(top: y, left: x, bottom: y, right: x); return s
    }
    /// The sprite cut to its visible pixels, so a small icon shows the pet and not the empty cell around it.
    static func trimmed(_ img: CGImage) -> CGImage {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = ctx.data else { return img }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 0 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= minX else { return img }
        return img.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? img  // memory rows run top-down, like cropping
    }
    /// Pixel art at icon size: trimmed, aspect-fit, nearest-neighbour so the pixels stay square.
    static func pixelIcon(_ img: CGImage, side: CGFloat) -> NSImage {
        let t = trimmed(img)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .none
            let k = min(r.width / CGFloat(t.width), r.height / CGFloat(t.height))
            let w = CGFloat(t.width) * k, h = CGFloat(t.height) * k
            ctx.draw(t, in: CGRect(x: (r.width - w) / 2, y: (r.height - h) / 2, width: w, height: h))
            return true
        }
    }
    /// A plain popup in a control-coloured box, so it sits with the other controls.
    static func popup(_ p: NSPopUpButton) -> NSView {
        p.isBordered = false
        p.font = body(12, .medium)
        (p.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        return wrap(padded(p, 2, 6), fill: control, radius: 6)
    }
}

/// A flat, layer-drawn block that re-resolves its dynamic colours when the theme changes.
final class Box: NSView {
    var fill: NSColor? { didSet { needsDisplay = true } }
    var stroke: NSColor? { didSet { needsDisplay = true } }
    var radius: CGFloat
    init(fill: NSColor?, radius: CGFloat = 0, stroke: NSColor? = nil) {
        self.fill = fill; self.radius = radius; self.stroke = stroke
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = fill?.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = stroke == nil ? 0 : 1.5
        layer?.borderColor = stroke?.cgColor
    }
}

/// Buttons: primary (the pet's colour, ink text), secondary (control fill), ghost (text only), icon (an SF Symbol).
final class Btn: NSButton {
    enum Style { case primary, secondary, ghost, icon }
    var style: Style { didSet { restyle() } }
    private var hovering = false { didSet { restyle() } }
    var small = false { didSet { restyle(); invalidateIntrinsicContentSize() } }
    /// Overrides the symbol colour (the selected sidebar item takes the pet's colour).
    var tint: NSColor? { didSet { restyle() } }

    init(_ title: String, style: Style = .secondary, symbol: String? = nil, target: AnyObject?, action: Selector?) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            imagePosition = title.isEmpty || style == .icon ? .imageOnly : .imageLeading
            if style == .icon { toolTip = title; setAccessibilityLabel(title); imageScaling = .scaleProportionallyUpOrDown; symbolConfiguration = .init(pointSize: 15, weight: .medium) }
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        if style == .icon { return NSSize(width: 30, height: 30) }
        return NSSize(width: s.width + (small ? 16 : 24), height: small ? 24 : 30)
    }
    override var isEnabled: Bool { didSet { restyle() } }
    override var alignment: NSTextAlignment { didSet { restyle() } }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle() }

    func restyle() {
        let color: NSColor
        var fill: NSColor?
        switch style {
        case .primary: fill = UI.accent; color = UI.ink
        case .secondary: fill = hovering ? UI.controlHover : UI.control; color = UI.fg
        case .ghost: fill = hovering ? UI.control : nil; color = hovering ? UI.fg : UI.text2
        case .icon: fill = hovering ? UI.control : nil; color = hovering ? UI.fg : UI.text2
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill?.withAlphaComponent(style == .primary && hovering ? 0.88 : (fill?.alphaComponent ?? 1)).cgColor
        }
        layer?.cornerRadius = 6
        alphaValue = isEnabled ? 1 : 0.4
        contentTintColor = tint ?? color
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        attributedTitle = NSAttributedString(string: style == .icon ? "" : title, attributes: [.font: UI.body(small ? 11 : 12, .semibold), .foregroundColor: color, .paragraphStyle: para])
    }
}

/// An on/off switch in the pet's colour. A real toggle button underneath, so `state` and the actions stay as they were.
final class Toggle: NSButton {
    private let track = CALayer(), knob = CALayer()
    override var state: NSControl.StateValue { didSet { redraw(animated: true) } }

    init(on: Bool, target: AnyObject?, action: Selector?, label: String) {
        super.init(frame: .zero)
        setButtonType(.toggle)
        isBordered = false
        title = ""
        self.target = target
        self.action = action
        wantsLayer = true
        track.cornerRadius = 10
        knob.cornerRadius = 8
        knob.shadowOpacity = 0.25; knob.shadowRadius = 1.5; knob.shadowOffset = CGSize(width: 0, height: -0.5)
        layer?.addSublayer(track); layer?.addSublayer(knob)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(label)
        state = on ? .on : .off
        redraw(animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 20) }
    override func layout() { super.layout(); redraw(animated: false) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); redraw(animated: false) }
    override func draw(_ dirtyRect: NSRect) {}  // the layers are the drawing

    private func redraw(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || reduceMotion)
        CATransaction.setAnimationDuration(0.16)  // snap
        let on = state == .on
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = (on ? UI.accent : UI.controlHover).cgColor
            knob.backgroundColor = (on ? UI.ink : UI.paper).cgColor
        }
        track.frame = CGRect(x: 0, y: 0, width: 36, height: 20)
        knob.frame = CGRect(x: on ? 18 : 2, y: 2, width: 16, height: 16)
        CATransaction.commit()
        setAccessibilityValue(on)
    }
}

/// A row of choices; the chosen one fills with the pet's colour. Momentary ones (Focus 25m) act and don't stay chosen.
final class Seg: NSControl {
    private(set) var buttons: [NSButton] = []
    var selectedSegment: Int = -1 { didSet { restyle() } }
    let momentary: Bool

    init(_ labels: [String], selected: Int, momentary: Bool = false, target: AnyObject?, action: Selector?) {
        self.momentary = momentary
        super.init(frame: .zero)
        self.target = target
        self.action = action
        wantsLayer = true
        let row = UI.hstack([], spacing: 2)
        row.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for (i, l) in labels.enumerated() {
            let b = NSButton(title: l, target: self, action: #selector(pick(_:)))
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 5
            b.tag = i
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            b.widthAnchor.constraint(greaterThanOrEqualToConstant: b.intrinsicContentSize.width + 18).isActive = true
            b.setAccessibilityRole(.radioButton)
            buttons.append(b)
            row.addArrangedSubview(b)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor)])
        selectedSegment = momentary ? -1 : selected
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = UI.control.cgColor; layer?.cornerRadius = 7; restyle() }

    @objc private func pick(_ b: NSButton) {
        selectedSegment = b.tag
        sendAction(action, to: target)
        if momentary { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.selectedSegment = -1 } }
    }
    private func restyle() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for b in buttons {
                let on = b.tag == selectedSegment
                b.layer?.backgroundColor = on ? UI.accent.cgColor : nil
                b.attributedTitle = NSAttributedString(string: b.title, attributes: [.font: UI.body(11, .semibold), .foregroundColor: on ? UI.ink : UI.text])
                b.setAccessibilityValue(on)
            }
        }
    }
}

/// A text field on a control-coloured box with room around the text; the pet's colour rings it while editing.
final class Field: NSTextField {
    final class Cell: NSTextFieldCell {
        private func inset(_ r: NSRect) -> NSRect {
            let h = font.map { ceil($0.ascender - $0.descender + $0.leading) } ?? 16
            return NSRect(x: r.minX + 10, y: r.minY + (r.height - h) / 2, width: r.width - 20, height: h)
        }
        override func drawingRect(forBounds r: NSRect) -> NSRect { inset(super.drawingRect(forBounds: r)) }
        override func edit(withFrame r: NSRect, in v: NSView, editor t: NSText, delegate d: Any?, event e: NSEvent?) {
            super.edit(withFrame: inset(r), in: v, editor: t, delegate: d, event: e)
        }
        override func select(withFrame r: NSRect, in v: NSView, editor t: NSText, delegate d: Any?, start s: Int, length l: Int) {
            super.select(withFrame: inset(r), in: v, editor: t, delegate: d, start: s, length: l)
        }
    }
    override class var cellClass: AnyClass? { get { Cell.self } set {} }

    convenience init(_ value: String, placeholder: String, width: CGFloat) {
        self.init(frame: .zero)
        stringValue = value
        placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.font: UI.body(12), .foregroundColor: UI.text3])
        isBezeled = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = UI.body(12)
        textColor = UI.fg
        wantsLayer = true
        (cell as? NSTextFieldCell)?.isScrollable = true
        (cell as? NSTextFieldCell)?.usesSingleLineMode = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        restyle(editing: false)
    }
    override func becomeFirstResponder() -> Bool { restyle(editing: true); return super.becomeFirstResponder() }
    override func textDidEndEditing(_ n: Notification) { super.textDidEndEditing(n); restyle(editing: false) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); restyle(editing: currentEditor() != nil) }
    private func restyle(editing: Bool) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = UI.control.cgColor
            layer?.borderColor = UI.accent.cgColor
        }
        layer?.cornerRadius = 6
        layer?.borderWidth = editing ? 1.5 : 0
    }
}

/// The menu bar surface: a borderless panel under the status item, radius 14, one shadow (D §1 Shape). It replaces
/// NSPopover, whose arrow and system material don't belong to the product's ink and paper.
final class MenuPanel: NSPanel {
    let surface = Box(fill: UI.surface, radius: 14)
    let scroll = NSScrollView()
    private var outside: Any?, inside: Any?
    var onClose: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        surface.layer?.masksToBounds = true
        surface.stroke = nil
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: surface.topAnchor), scroll.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
                                     scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor)])
        contentView = surface
    }
    override var canBecomeKey: Bool { true }

    /// Sizes the panel to `content` (capped to the screen, scrolling past that) and pins it under `button`.
    func fit(_ content: NSView, under button: NSStatusBarButton?) {
        if content.superview == nil || content.superview !== scroll.documentView { scroll.documentView = FlippedClip.wrap(content) }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        guard let bw = button?.window, let screen = bw.screen ?? NSScreen.main else { return }
        let r = bw.frame
        let h = min(size.height, screen.visibleFrame.height - 24)
        let x = min(max(r.midX - size.width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        setFrame(NSRect(x: x, y: r.minY - 6 - h, width: size.width, height: h), display: true)
        (scroll.documentView)?.frame.size = size
    }

    func open() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        let end = frame
        if !reduceMotion { setFrameOrigin(NSPoint(x: end.minX, y: end.minY + 6)) }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = reduceMotion ? 0.12 : 0.28  // settle
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1, 0.4, 1)
            animator().alphaValue = 1
            if !reduceMotion { animator().setFrame(end, display: true) }
        }
        // a click anywhere else, or esc, folds it away
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.dismiss() }
        inside = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            if e.keyCode == 53, self?.isKeyWindow == true { self?.dismiss(); return nil }
            return e
        }
    }
    func dismiss() {
        guard isVisible else { return }
        [outside, inside].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        outside = nil; inside = nil
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.orderOut(nil); self?.alphaValue = 1 })
        onClose?()
    }
}

/// Scroll views lay out from the bottom; this keeps the content's top at the top.
final class FlippedClip: NSView {
    override var isFlipped: Bool { true }
    static func wrap(_ v: NSView) -> NSView {
        let f = FlippedClip()
        v.translatesAutoresizingMaskIntoConstraints = false
        f.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: f.topAnchor), v.leadingAnchor.constraint(equalTo: f.leadingAnchor)])
        return f
    }
}
