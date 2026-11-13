import CoreGraphics
import Foundation
import Testing
@testable import GremloCore

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let petsDir = repo.appendingPathComponent("assets/pets")

func realPack(_ id: String) throws -> Pack { try Pack.decode(Data(contentsOf: petsDir.appendingPathComponent("\(id)/pet.json"))) }

/// A minimal pet.json for older pack versions: the first `count` v6 rows, with only the fields that version had.
func fixture(rows count: Int, plate: Bool, head: Bool, version: Int? = nil) throws -> Pack {
    let names = Row.allCases.prefix(count)
    var rows: [String: Any] = [:]
    for (i, r) in names.enumerated() { rows[r.rawValue] = ["row": i, "frames": 4] }
    var meta: [String: Any] = ["species": "test", "accent": "#FF5A3C", "cell": [192, 208], "columns": 8, "rows": rows]
    if plate {
        meta["plateAnchor"] = Array(repeating: [96, 47], count: 4)
        meta["signKit"] = ["path": "signkit.png", "size": [20, 11], "slice": ["top": 3, "right": 4, "bottom": 3, "left": 4], "scale": 3]
        meta["anchors"] = ["edgepeek": "left", "thrown": "centre", "peek": "top"]
    }
    if head { meta["headAnchor"] = names.map { _ in [[85, 54, 7], NSNull(), [90, 74, 6], [90, 74, 6]] } }
    var json: [String: Any] = ["id": "test", "displayName": "Test", "gremlo": meta]
    if let version { json["spriteVersionNumber"] = version }
    return try Pack.decode(JSONSerialization.data(withJSONObject: json))
}

@Suite struct Loader {
    @Test func allEightRealPacksAreV6WithEveryRow() throws {
        for s in Roster.all {
            let p = try realPack(s.id)
            #expect(p.version == 6, "\(s.id)")
            #expect(p.gremlo.rows.count == 39, "\(s.id)")
            for row in Row.allCases { #expect(p.spec(row) != nil, "\(s.id) lacks \(row)") }
            #expect(p.canHoldLine, "\(s.id)")
            #expect(p.gremlo.accent.uppercased() == s.accent.uppercased(), "\(s.id) accent")
            #expect(p.gremlo.accessories?.names.count == 12)
        }
    }

    @Test func versionsAreInferredWhenNotDeclared() throws {
        #expect(try fixture(rows: 15, plate: false, head: false).version == 3)
        #expect(try fixture(rows: 29, plate: true, head: false).version == 4)
        #expect(try fixture(rows: 31, plate: true, head: true).version == 5)
        #expect(try fixture(rows: 39, plate: true, head: true).version == 6)
        #expect(try fixture(rows: 15, plate: false, head: false, version: 4).version == 4, "a declared version wins")
    }

    @Test func v3PackFallsBackAndCannotHoldTheLine() throws {
        let p = try fixture(rows: 15, plate: false, head: false)
        #expect(!p.canHoldLine)
        #expect(Fallback.resolve(.hold, in: p) == Resolved(row: .sign, frames: nil, rotated: false))
        #expect(Fallback.resolve(.gaze, in: p) == Resolved(row: .idle, frames: [0], rotated: false))
        #expect(Fallback.resolve(.land, in: p) == Resolved(row: .fail, frames: [0, 1], rotated: false))
        #expect(Fallback.resolve(.tools, in: p) == nil, "no tools row: no prop, never a wrong one")
        #expect(Fallback.resolve(.walk, in: p) == Resolved(row: .walk, frames: nil, rotated: false))
        #expect(p.head(.idle, frame: 0) == nil, "v3 has no head anchors, so accessories hide")
    }

    @Test func climbFallsBackToWalkRotated() throws {
        // a pack whose climb row is missing (a Codex import, say)
        let json: [String: Any] = ["id": "c", "displayName": "C", "gremlo": ["species": "c", "accent": "#000000", "cell": [192, 208], "columns": 8,
                                                                         "rows": ["walk": ["row": 0, "frames": 8], "idle": ["row": 1, "frames": 4]]]]
        let p = try Pack.decode(JSONSerialization.data(withJSONObject: json))
        #expect(Fallback.resolve(.climb, in: p) == Resolved(row: .walk, frames: nil, rotated: true))
        #expect(Fallback.resolve(.night, in: p) == Resolved(row: .idle, frames: [0], rotated: false), "frames 5-6 don't exist in a 4-frame idle")
    }

    @Test func v4HasPlateButNoHeadAnchors() throws {
        let p = try fixture(rows: 29, plate: true, head: false)
        #expect(p.canHoldLine)
        #expect(p.plateAnchor(frame: 2)! == (96, 47))
        #expect(p.head(.idle, frame: 0) == nil)
        #expect(p.anchor(.edgepeek) == .left && p.anchor(.thrown) == .centre && p.anchor(.peek) == .top && p.anchor(.walk) == .feet)
    }

    @Test func v5HeadAnchorsAndNullFrames() throws {
        let p = try fixture(rows: 31, plate: true, head: true)
        #expect(p.head(.idle, frame: 0)! == (85, 54, 7))
        #expect(p.head(.idle, frame: 1) == nil, "null hides accessories on that frame")
        #expect(p.head(.idle, frame: 99) == nil)
    }

    @Test func realPacksHideAccessoriesWhereTheSpecSays() throws {
        let hidden: [Row] = [.climb, .evolve, .peek, .edgepeek, .thrown, .hatch, .covereyes, .tangled, .backflip, .moonwalk]
        for s in Roster.all {
            let p = try realPack(s.id)
            for row in hidden { #expect(p.head(row, frame: 0) == nil, "\(s.id) \(row) should hide accessories") }
            #expect(p.head(.idle, frame: 0) != nil, "\(s.id) idle shows accessories")
        }
    }
}
