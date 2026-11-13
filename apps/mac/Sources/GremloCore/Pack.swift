import Foundation

// A species pack: assets/pets/<id>/{pet.json, spritesheet.webp, signkit.png, accessories.png}.
// Codex desktop-pet layout extended by the 1.0 design: 192 x 208 cells, 8 columns, feet on y=194.
// v3 has 15 rows, v4 29 (plate anchors, sign kit, anchors), v5 31 (head anchors, accessories), v6 39 (arcs).

/// Every row name the 1.0 design defines, in sheet order (v6).
public enum Row: String, CaseIterable, Sendable {
    case eat, walk, climb, greet, celebrate, idle, sign, flag, fail, hover, annoy, special, evolve, wardrobe, peek
    case turn, startstop, gaze, sit, edgepeek, yawn, grabbed, thrown, land, social, tools, night, focus, hold
    case wardrobe2, hatch
    case chase, gulp, covereyes, tangled, backflip, juggle, moonwalk, wrist
}

public struct RowSpec: Codable, Equatable, Sendable { public let row: Int; public let frames: Int }

public struct SignKit: Codable, Equatable, Sendable {
    public struct Slice: Codable, Equatable, Sendable { public let top, right, bottom, left: Int }
    public let path: String
    public let size: [Int]     // kit pixels, [20, 11]
    public let slice: Slice
}

public struct AccessorySheet: Codable, Equatable, Sendable {
    public let names: [String]
    public let cell: [Int]     // sprite units, [40, 40]
    public let anchor: [Int]   // the point that sits on headAnchor, [20, 12]
    public let path: String
}

public struct PackMeta: Codable, Sendable {
    public let species: String
    public let accent: String
    public let cell: [Int]
    public let columns: Int
    public let rows: [String: RowSpec]
    public let signRect: [[Int]]?
    public let plateAnchor: [[Int]]?
    public let signKit: SignKit?
    /// headAnchor[row][frame] = [x, y, unitPx] in cell px, or null where accessories hide.
    public let headAnchor: [[[Int]?]?]?
    public let accessories: AccessorySheet?
    public let anchors: [String: String]?
    public let arcs: [String: String]?
}

public struct Pack: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let spriteVersionNumber: Int?
    public let spritesheetPath: String?
    public let gremlo: PackMeta

    enum CodingKeys: String, CodingKey { case id, displayName, description, spriteVersionNumber, spritesheetPath, gremlo, notchi }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        spriteVersionNumber = try c.decodeIfPresent(Int.self, forKey: .spriteVersionNumber)
        spritesheetPath = try c.decodeIfPresent(String.self, forKey: .spritesheetPath)
        // packs made before the rename keep their metadata under the old key (Legacy.packKey)
        gremlo = try c.decodeIfPresent(PackMeta.self, forKey: .gremlo) ?? c.decode(PackMeta.self, forKey: .notchi)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(displayName, forKey: .displayName)
        try c.encodeIfPresent(description, forKey: .description); try c.encodeIfPresent(spriteVersionNumber, forKey: .spriteVersionNumber)
        try c.encodeIfPresent(spritesheetPath, forKey: .spritesheetPath); try c.encode(gremlo, forKey: .gremlo)
    }

    public var sheetPath: String { spritesheetPath ?? "spritesheet.webp" }
    public var cell: (w: Int, h: Int) { (gremlo.cell.first ?? 192, gremlo.cell.count > 1 ? gremlo.cell[1] : 208) }

    /// The pack version: the declared number, else inferred from what the pack carries.
    public var version: Int {
        if let v = spriteVersionNumber { return v }
        switch gremlo.rows.count {
        case 39...: return 6
        case 31...: return 5
        case 29...: return 4
        default: return 3
        }
    }

    public func spec(_ row: Row) -> RowSpec? { gremlo.rows[row.rawValue] }

    /// Holding the line needs the hold row, plate anchors and a sign kit; a pack without them can't be the earner.
    public var canHoldLine: Bool { spec(.hold) != nil && (gremlo.plateAnchor?.isEmpty == false) && gremlo.signKit != nil }

    /// headAnchor for a frame, or nil where accessories hide (or the pack has no anchors).
    public func head(_ row: Row, frame: Int) -> (x: Int, y: Int, unitPx: Int)? {
        guard let r = spec(row), let rows = gremlo.headAnchor, r.row < rows.count, let frames = rows[r.row],
              frame >= 0, frame < frames.count, let a = frames[frame], a.count >= 3 else { return nil }
        return (a[0], a[1], a[2])
    }

    public func plateAnchor(frame: Int) -> (x: Int, y: Int)? {
        guard let p = gremlo.plateAnchor, !p.isEmpty else { return nil }
        let a = p[min(max(frame, 0), p.count - 1)]
        return a.count >= 2 ? (a[0], a[1]) : nil
    }

    public static func decode(_ data: Data) throws -> Pack { try JSONDecoder().decode(Pack.self, from: data) }
}

/// Where a row's frames come from when a pack doesn't have it (older packs, Codex imports).
public struct Resolved: Equatable, Sendable {
    public let row: Row          // the row actually drawn
    public let frames: [Int]?    // a subset of that row's frames, or all
    public let rotated: Bool     // climb drawn from walk, rotated onto the wall
}

public enum Fallback {
    /// Spec R2 §13 for the named cases; the rest borrow the closest row that every pack has.
    static let table: [Row: (Row, [Int]?, Bool)] = [
        .climb: (.walk, nil, true),
        .gaze: (.idle, [0], false),
        .land: (.fail, [0, 1], false),
        .turn: (.walk, nil, false),
        .startstop: (.walk, nil, false),
        .sit: (.idle, [0], false),
        .edgepeek: (.peek, nil, false),
        .yawn: (.idle, nil, false),
        .grabbed: (.annoy, [0], false),
        .thrown: (.annoy, [0], false),
        .social: (.greet, nil, false),
        .night: (.idle, [5, 6], false),
        .focus: (.idle, [0], false),
        .hold: (.sign, nil, false),
        .wardrobe2: (.wardrobe, nil, false),
        .hatch: (.evolve, [0, 1, 2], false),
        .chase: (.walk, nil, false),
        .gulp: (.eat, nil, false),
        .covereyes: (.fail, nil, false),
        .tangled: (.fail, nil, false),
        .backflip: (.special, nil, false),
        .juggle: (.special, nil, false),
        .moonwalk: (.walk, nil, false),
        .wrist: (.idle, [7], false),
    ]

    /// The row to draw for `row` in `pack`, or nil when nothing fits (tools: no prop rather than a wrong one).
    public static func resolve(_ row: Row, in pack: Pack) -> Resolved? {
        if pack.spec(row) != nil { return Resolved(row: row, frames: nil, rotated: false) }
        if row == .tools { return nil }
        guard let (alt, frames, rotated) = table[row] else { return pack.spec(.walk) != nil ? Resolved(row: .walk, frames: nil, rotated: false) : nil }
        guard let altSpec = pack.spec(alt) else { return nil }
        let fit = frames?.filter { $0 < altSpec.frames }
        return Resolved(row: alt, frames: (fit?.isEmpty ?? true) ? (frames == nil ? nil : [0]) : fit, rotated: rotated)
    }
}
