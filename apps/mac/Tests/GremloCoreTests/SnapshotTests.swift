import CoreGraphics
import Foundation
import Testing
@testable import GremloCore

// Snapshot tests (spec R2 M1, R3 step 2). References live next to this file; GREMLO_RECORD=1 rewrites them.
// A test fails when more than 0.5% of pixels differ beyond a small tolerance (font rasterising varies a little).

let snapshotsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
let recording = Legacy.env("RECORD") == "1"

func assertSnapshot(_ image: CGImage?, named name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let img = try #require(image, "\(name): nothing rendered", sourceLocation: sourceLocation)
    let url = snapshotsDir.appendingPathComponent("\(name).png")
    if recording || !FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        try #require(Images.png(img), sourceLocation: sourceLocation).write(to: url)
        if !recording { Issue.record("\(name): no reference yet; recorded one, review and commit it", sourceLocation: sourceLocation) }
        return
    }
    let ref = try #require(Images.load(url), sourceLocation: sourceLocation)
    let diff = Images.difference(img, ref)
    #expect(diff <= 0.005, "\(name): \(String(format: "%.2f", diff * 100))% of pixels changed", sourceLocation: sourceLocation)
}

@Suite(.serialized) struct Snapshots {
    let line = "Ship faster with Acme CI"

    @Test func signPlateAt1xAnd2xForAllEightSpecies() throws {
        for s in Roster.all {
            let pack = try LoadedPack.load(dir: petsDir.appendingPathComponent(s.id))
            let kit = try #require(pack.pack.gremlo.signKit)
            let kitImage = try #require(pack.kit)
            for backing in [1.0, 2.0] {
                let r = PlateRenderer.render(line: line, kitImage: kitImage, kit: kit, scale: 2.0 / 7, backing: backing)
                try assertSnapshot(r?.0, named: "plate-\(s.id)-\(Int(backing))x")
            }
        }
    }

    @Test func allTwelveAccessoriesOnAllEightSpeciesIdleFrameZero() throws {
        for s in Roster.all {
            let pack = try LoadedPack.load(dir: petsDir.appendingPathComponent(s.id))
            let names = try #require(pack.pack.gremlo.accessories?.names)
            #expect(names.count == 12)
            for name in names {
                try assertSnapshot(PetRenderer.render(pack, row: .idle, frame: 0, worn: [name], scale: 0.5), named: "acc-\(s.id)-\(name)")
            }
        }
    }

    /// What the earner looks like holding the line: the hold frame with the plate on its anchor, as the Mac draws it.
    @Test func earnerHoldingTheLineForAllEightSpecies() throws {
        for s in Roster.all {
            let loaded = try LoadedPack.load(dir: petsDir.appendingPathComponent(s.id))
            let scale: CGFloat = 2.0 / 7, backing: CGFloat = 2
            let (plateImg, layout) = try #require(PlateRenderer.render(line: line, kitImage: loaded.kit!, kit: loaded.pack.gremlo.signKit!, scale: scale, backing: backing))
            let g = PetGeometry(cellW: loaded.pack.cell.w, cellH: loaded.pack.cell.h, scale: scale)
            let r = try #require(Plate.frame(layout, pack: loaded.pack, frame: 0, geometry: g, flipped: false))
            let petW = g.cellW * scale, petH = g.cellH * scale
            let plateW = CGFloat(plateImg.width) / backing, plateH = CGFloat(plateImg.height) / backing
            let W = max(petW, plateW) + 8, H = max(petH, r.minY + plateH) + 4
            let ctx = try #require(Images.context(Int(W * backing), Int(H * backing)))
            ctx.scaleBy(x: backing, y: backing)
            let ox = (W - petW) / 2
            ctx.draw(try #require(loaded.frames[.hold]?.first), in: CGRect(x: ox, y: 0, width: petW, height: petH))
            ctx.draw(plateImg, in: CGRect(x: ox + r.midX - plateW / 2, y: r.minY, width: plateW, height: plateH))
            try assertSnapshot(ctx.makeImage(), named: "earner-\(s.id)")
        }
    }

    @Test func everyRowOfEveryPackCropsWithAllItsFrames() throws {
        for s in Roster.all {
            let pack = try LoadedPack.load(dir: petsDir.appendingPathComponent(s.id))
            for row in Row.allCases {
                #expect(pack.frames[row]?.count == pack.pack.spec(row)?.frames, "\(s.id) \(row)")
            }
            #expect(pack.kit != nil && pack.accessories != nil)
        }
    }
}
