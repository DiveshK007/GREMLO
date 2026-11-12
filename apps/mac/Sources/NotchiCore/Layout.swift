import CoreGraphics
import Foundation

// Pure geometry and timing for drawing a pack. Cell coordinates are sheet pixels with y down from the cell's top;
// local coordinates are points in the pet's own view, origin bottom-left (AppKit), size = cell x scale.

public enum Rates {
    /// Base frames per second (spec D §3, R2 §1). nil: no clock, the app picks the frame (gaze, tools, evolve...).
    /// The round 4 rows have no rate in the spec; those values are ours (marked).
    public static let base: [Row: Double] = [
        .eat: 6, .walk: 8, .climb: 8, .greet: 5.5, .celebrate: 10, .idle: 2.4, .sign: 5, .flag: 10, .fail: 7,
        .hover: 3.5, .annoy: 10, .special: 4, .peek: 2, .turn: 10, .startstop: 12, .sit: 3, .edgepeek: 4, .yawn: 3,
        .grabbed: 8, .thrown: 16, .land: 10, .social: 8, .night: 2.4, .focus: 2, .hold: 4.5,
        // not in the spec: chosen to read clearly at the pet's size
        .chase: 10, .gulp: 8, .covereyes: 6, .tangled: 4, .juggle: 8, .moonwalk: 8, .wrist: 4,
        // backflip: six frames over the 0.5 s jump arc
        .backflip: 12,
    ]
    /// Mood scales the rate, never the frames (spec D §3).
    public static func multiplier(mood: String) -> Double {
        switch mood {
        case "thriving": return 1.25
        case "hungry": return 0.6
        default: return 1
        }
    }
    public static func fps(_ row: Row, mood: String) -> Double? { base[row].map { $0 * multiplier(mood: mood) } }
}

public enum Sequence {
    /// Frame order within a row of `n` frames. Idle: 0-3 loop, 4 hungry, 5-6 asleep (spec D §3).
    /// Annoy: 1-2 clicks frame 0, 3-4 frames 1-2, 5+ frames 3-5.
    public static func frames(_ row: Row, count n: Int, mood: String = "stable", clicks: Int = 0) -> [Int] {
        guard n > 0 else { return [0] }
        let fit: ([Int]) -> [Int] = { want in let f = want.filter { $0 < n }; return f.isEmpty ? [0] : f }
        switch row {
        case .idle where n >= 8:
            switch mood {
            case "hungry": return [4]
            case "asleep": return [5, 6]
            default: return [0, 1, 2, 3]
            }
        case .annoy:
            return fit(clicks >= 5 ? [3, 4, 5] : clicks >= 3 ? [1, 2] : [0])
        case .celebrate:
            return Array(0..<n) + Array(0..<n)
        default:
            return Array(0..<n)
        }
    }
}

/// How a row's frame sits relative to the pet's position (spec R2 §1): feet unless the pack says otherwise.
public enum Anchor: String, Sendable { case feet, left, centre, top }

public extension Pack {
    func anchor(_ row: Row) -> Anchor { notchi.anchors?[row.rawValue].flatMap(Anchor.init(rawValue:)) ?? .feet }
}

public struct PetGeometry: Sendable {
    public let cellW: CGFloat, cellH: CGFloat, scale: CGFloat   // scale: points per sheet pixel
    public init(cellW: Int, cellH: Int, scale: CGFloat) { self.cellW = CGFloat(cellW); self.cellH = CGFloat(cellH); self.scale = scale }

    /// A point in cell px to local points, mirrored when the sprite faces left.
    public func local(_ x: CGFloat, _ y: CGFloat, flipped: Bool) -> CGPoint {
        CGPoint(x: (flipped ? cellW - x : x) * scale, y: (cellH - y) * scale)
    }
}

// MARK: - The sign plate (spec R2 §2)

public struct PlateLayout: Equatable, Sendable {
    public let kitPx: CGFloat          // points per kit pixel, a whole number >= 3
    public let size: CGSize            // the whole plate, points
    public let textRect: CGRect        // where the line sits, points, origin bottom-left of the plate
    public let fontSize: CGFloat       // 3.7 kit px
    public let adTab: CGRect           // the AD disclosure tab, above the top-right corner
}

public enum Plate {
    /// One kit pixel = max(3, round(7 x scale)) points, always whole (spec R2 M1 step 4). 7 = one sprite unit.
    public static func kitPx(scale: CGFloat) -> CGFloat { max(3, (7 * scale).rounded()) }

    /// The plate for a line whose text measures `textWidth` points at `fontSize(kitPx:)`. The face stretches; the
    /// slices don't. Never truncated or scrolled: a longer line makes a wider plate.
    public static func layout(textWidth: CGFloat, kit: SignKit, scale: CGFloat) -> PlateLayout {
        let k = kitPx(scale: scale)
        let base = CGSize(width: CGFloat(kit.size.first ?? 20), height: CGFloat(kit.size.count > 1 ? kit.size[1] : 11))
        let sl = kit.slice
        let padding: CGFloat = 1 // one kit px of paper either side of the text
        let faceUnits = max(base.width - CGFloat(sl.left + sl.right), (textWidth / k).rounded(.up) + 2 * padding)
        let w = (CGFloat(sl.left + sl.right) + faceUnits) * k, h = base.height * k
        let font = fontSize(kitPx: k)
        let textH = (font * 1.25).rounded(.up)
        let text = CGRect(x: (CGFloat(sl.left) + padding) * k, y: ((h - textH) / 2).rounded(), width: textWidth, height: textH)
        let tab = CGRect(x: w - 7 * k, y: h - k, width: 7 * k, height: 4 * k)
        return PlateLayout(kitPx: k, size: CGSize(width: w, height: h), textRect: text, fontSize: font, adTab: tab)
    }

    public static func fontSize(kitPx: CGFloat) -> CGFloat { (kitPx * 3.7 * 10).rounded() / 10 }

    /// The plate's frame in the pet's local points: bottom-centre on plateAnchor x scale. The sprite may flip;
    /// the plate follows the anchor but is never mirrored.
    public static func frame(_ plate: PlateLayout, pack: Pack, frame: Int, geometry g: PetGeometry, flipped: Bool) -> CGRect? {
        guard let a = pack.plateAnchor(frame: frame) else { return nil }
        let p = g.local(CGFloat(a.x), CGFloat(a.y), flipped: flipped)
        return CGRect(x: (p.x - plate.size.width / 2).rounded(), y: p.y.rounded(), width: plate.size.width, height: plate.size.height)
    }

    /// Lines are 6-40 characters; the console enforces it, the plate shows whatever it is given in full.
    public static let lineLength = 6...40
}

// MARK: - Accessories (spec R3 §1)

public enum Accessories {
    /// Rect of item `index` in accessories.png (pixels, y down).
    public static func sourceRect(index: Int, sheet: AccessorySheet) -> CGRect {
        let w = sheet.cell.first ?? 40, h = sheet.cell.count > 1 ? sheet.cell[1] : 40
        return CGRect(x: index * w, y: 0, width: w, height: h)
    }

    /// Where an accessory draws in the pet's local points for this frame, or nil where accessories hide.
    /// The cell scales by unitPx x pet scale and its anchor sits on headAnchor. It mirrors with the sprite.
    public static func frame(sheet: AccessorySheet, pack: Pack, row: Row, frame: Int,
                             geometry g: PetGeometry, flipped: Bool) -> CGRect? {
        guard let head = pack.head(row, frame: frame) else { return nil }
        let u = CGFloat(head.unitPx)
        let cw = CGFloat(sheet.cell.first ?? 40), ch = CGFloat(sheet.cell.count > 1 ? sheet.cell[1] : 40)
        let ax = CGFloat(sheet.anchor.first ?? 20), ay = CGFloat(sheet.anchor.count > 1 ? sheet.anchor[1] : 12)
        // the box in cell px, unmirrored; when the sprite faces left the whole box mirrors about the cell centre
        let left = CGFloat(head.x) - ax * u, top = CGFloat(head.y) - ay * u
        let w = cw * u * g.scale, h = ch * u * g.scale
        let x = (flipped ? g.cellW - (left + cw * u) : left) * g.scale
        let y = (g.cellH - top) * g.scale - h
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Worn items in draw order: neck, face, head; one per slot (the later choice wins).
    public static func drawOrder(_ worn: [String]) -> [String] {
        var bySlot: [Slot: String] = [:]
        for item in worn { bySlot[Slot.of(item)] = item }
        return bySlot.sorted { $0.key < $1.key }.map(\.value)
    }
}

// MARK: - Arcs (spec R4 §1)

public enum Arcs {
    public static let backflipSeconds = 0.5
    public static let backflipPeak = 1.6

    /// The pet's body height in cell px: baseline to the head anchor on idle frame 0, else 45% of the cell.
    public static func bodyHeight(_ pack: Pack, baseline: Int = 194) -> CGFloat {
        if let h = pack.head(.idle, frame: 0) { return CGFloat(baseline - h.y) }
        return CGFloat(pack.cell.h) * 0.45
    }

    /// Height above the ground at `t` seconds into a backflip (frames 1-4 are airborne): a parabola peaking at
    /// 1.6 x body height halfway through 0.5 s, zero outside the jump.
    public static func backflipLift(t: Double, bodyHeight: CGFloat) -> CGFloat {
        guard t > 0, t < backflipSeconds else { return 0 }
        let u = t / backflipSeconds
        return CGFloat(4 * u * (1 - u)) * bodyHeight * CGFloat(backflipPeak)
    }

    /// Moonwalk: the pet faces `facing` (+1 right, -1 left) and slides the other way at walking pace.
    public static func moonwalkVelocity(facing: CGFloat, walkPointsPerSecond: CGFloat) -> CGFloat { -facing * walkPointsPerSecond }
}
