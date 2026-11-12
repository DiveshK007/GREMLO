import CoreGraphics
import CoreText
import Foundation
import ImageIO

// Offscreen drawing for packs: sheet frames, the sign plate and accessories. CoreGraphics only, so the same code
// runs in the app and in snapshot tests.

public enum Images {
    public static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// RGBA context of `size` pixels, origin bottom-left, nearest-neighbour.
    public static func context(_ w: Int, _ h: Int) -> CGContext? {
        let ctx = CGContext(data: nil, width: max(w, 1), height: max(h, 1), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .none
        return ctx
    }

    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Fraction of pixels whose RGBA differs by more than `tolerance` (0...255) in any channel. 1 if sizes differ.
    public static func difference(_ a: CGImage, _ b: CGImage, tolerance: Int = 24) -> Double {
        guard a.width == b.width, a.height == b.height, let pa = rgba(a), let pb = rgba(b) else { return 1 }
        var off = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            for c in 0..<4 where abs(Int(pa[i + c]) - Int(pb[i + c])) > tolerance { off += 1; break }
        }
        return Double(off) / Double(a.width * a.height)
    }

    static func rgba(_ img: CGImage) -> [UInt8]? {
        guard let ctx = context(img.width, img.height) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard let data = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: ctx.bytesPerRow * img.height))
    }
}

/// A loaded pack: the parsed pet.json plus its images.
public struct LoadedPack {
    public let pack: Pack
    public let dir: URL
    public let frames: [Row: [CGImage]]
    public let kit: CGImage?
    public let accessories: CGImage?

    public static func load(dir: URL) throws -> LoadedPack {
        let pack = try Pack.decode(Data(contentsOf: dir.appendingPathComponent("pet.json")))
        guard let sheet = Images.load(dir.appendingPathComponent(pack.sheetPath)) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: dir.appendingPathComponent(pack.sheetPath).path])
        }
        let (cw, ch) = pack.cell
        var frames: [Row: [CGImage]] = [:]
        for row in Row.allCases {
            guard let spec = pack.spec(row), spec.frames > 0 else { continue }
            let cut = (0..<spec.frames).compactMap { sheet.cropping(to: CGRect(x: $0 * cw, y: spec.row * ch, width: cw, height: ch)) }
            if cut.count == spec.frames { frames[row] = cut }
        }
        let kit = pack.notchi.signKit.flatMap { Images.load(dir.appendingPathComponent($0.path)) }
        let acc = pack.notchi.accessories.flatMap { Images.load(dir.appendingPathComponent($0.path)) }
        return LoadedPack(pack: pack, dir: dir, frames: frames, kit: kit, accessories: acc)
    }

    /// The frames to draw for `row`, falling back per Fallback.resolve; nil when nothing fits.
    public func strip(_ row: Row) -> (frames: [CGImage], rotated: Bool)? {
        guard let r = Fallback.resolve(row, in: pack), let all = frames[r.row] else { return nil }
        let pick = r.frames.map { $0.compactMap { $0 < all.count ? all[$0] : nil } } ?? all
        return pick.isEmpty ? nil : (pick, r.rotated)
    }

    public func accessory(_ name: String) -> CGImage? {
        guard let sheet = pack.notchi.accessories, let img = accessories, let i = sheet.names.firstIndex(of: name) else { return nil }
        return img.cropping(to: Accessories.sourceRect(index: i, sheet: sheet))
    }
}

public enum Fonts {
    private static let registered: Bool = {
        // the repo's assets/fonts, or the app bundle's copy
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("assets/fonts/Inter-Variable.ttf"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets/fonts/Inter-Variable.ttf"),
        ].compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let url = candidates.first else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) || true
    }()

    /// Inter at `weight` (100-900), or the system font if Inter isn't available.
    public static func inter(_ size: CGFloat, weight: CGFloat = 600) -> CTFont {
        _ = registered
        let wght = 0x77676874 // 'wght'
        let attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: "Inter", kCTFontVariationAttribute: [wght: weight]]
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attrs as CFDictionary), size, nil)
        return font
    }

    public static func width(_ text: String, font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

public enum PlateRenderer {
    static let ink = CGColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255, alpha: 1)
    static let paper = CGColor(srgbRed: 0xF4 / 255, green: 0xF2 / 255, blue: 0xED / 255, alpha: 1)

    /// The plate for `line`, at `backing` pixels per point. Ink text on the kit's paper face; an AD tab on the
    /// top-right corner. Returns the image and its layout in points.
    /// `sponsored: false` (a teammate's visit, never an ad) leaves the AD tab off.
    public static func render(line: String, kitImage: CGImage, kit: SignKit, scale: CGFloat, backing: CGFloat = 2, sponsored: Bool = true) -> (CGImage, PlateLayout)? {
        let probe = Plate.layout(textWidth: 0, kit: kit, scale: scale)
        let font = Fonts.inter(probe.fontSize)
        let layout = Plate.layout(textWidth: Fonts.width(line, font: font).rounded(.up), kit: kit, scale: scale)
        let tabExtra = layout.adTab.maxY - layout.size.height
        let W = Int((layout.size.width * backing).rounded()), H = Int(((layout.size.height + tabExtra) * backing).rounded())
        guard let ctx = Images.context(W, H) else { return nil }
        ctx.scaleBy(x: backing, y: backing)
        nineSlice(ctx, kitImage, kit: kit, into: CGRect(origin: .zero, size: layout.size), kitPx: layout.kitPx)
        // AD tab: ink with paper letters, sitting on the top-right corner
        if sponsored {
            ctx.setFillColor(ink)
            ctx.fill(layout.adTab)
            draw("AD", ctx, font: Fonts.inter(layout.kitPx * 2.6, weight: 700), color: paper,
                 in: layout.adTab, centred: true)
        }
        draw(line, ctx, font: font, color: ink, in: layout.textRect, centred: false)
        return ctx.makeImage().map { ($0, layout) }
    }

    /// Nine-slice with nearest-neighbour scaling: corners at kitPx per kit pixel, edges and face stretched.
    static func nineSlice(_ ctx: CGContext, _ img: CGImage, kit: SignKit, into r: CGRect, kitPx k: CGFloat) {
        let sw = CGFloat(img.width), sh = CGFloat(img.height)
        let s = kit.slice
        let L = CGFloat(s.left), R = CGFloat(s.right), T = CGFloat(s.top), B = CGFloat(s.bottom)
        let xs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, L, r.minX, L * k), (L, sw - L - R, r.minX + L * k, r.width - (L + R) * k), (sw - R, R, r.maxX - R * k, R * k)]
        // source rows top-down; destination rows bottom-up
        let ys: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, T, r.maxY - T * k, T * k), (T, sh - T - B, r.minY + B * k, r.height - (T + B) * k), (sh - B, B, r.minY, B * k)]
        ctx.interpolationQuality = .none
        for (sy, shh, dy, dh) in ys {
            for (sx, sww, dx, dw) in xs {
                guard sww > 0, shh > 0, dw > 0, dh > 0, let part = img.cropping(to: CGRect(x: sx, y: sy, width: sww, height: shh)) else { continue }
                ctx.draw(part, in: CGRect(x: dx, y: dy, width: dw, height: dh))
            }
        }
    }

    static func draw(_ text: String, _ ctx: CGContext, font: CTFont, color: CGColor, in r: CGRect, centred: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let x = centred ? r.midX - w / 2 : r.minX
        let y = r.midY - (ascent - descent) / 2
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}

public enum PetRenderer {
    /// One frame with the worn accessories on top, at `scale` points per sheet pixel and `backing` pixels per point.
    public static func render(_ loaded: LoadedPack, row: Row, frame: Int, worn: [String], scale: CGFloat, backing: CGFloat = 1, flipped: Bool = false) -> CGImage? {
        guard let strip = loaded.strip(row), frame < strip.frames.count else { return nil }
        let (cw, ch) = loaded.pack.cell
        let g = PetGeometry(cellW: cw, cellH: ch, scale: scale)
        let W = Int((CGFloat(cw) * scale * backing).rounded()), H = Int((CGFloat(ch) * scale * backing).rounded())
        guard let ctx = Images.context(W, H) else { return nil }
        ctx.scaleBy(x: backing, y: backing)
        func put(_ img: CGImage, _ r: CGRect) {
            ctx.saveGState()
            if flipped { ctx.translateBy(x: r.midX, y: 0); ctx.scaleBy(x: -1, y: 1); ctx.translateBy(x: -r.midX, y: 0) }
            ctx.draw(img, in: r)
            ctx.restoreGState()
        }
        put(strip.frames[frame], CGRect(x: 0, y: 0, width: g.cellW * scale, height: g.cellH * scale))
        if let sheet = loaded.pack.notchi.accessories {
            for name in Accessories.drawOrder(worn) {
                guard let img = loaded.accessory(name),
                      let r = Accessories.frame(sheet: sheet, pack: loaded.pack, row: row, frame: frame, geometry: g, flipped: flipped) else { continue }
                put(img, r)
            }
        }
        return ctx.makeImage()
    }
}
