import CoreGraphics
import Foundation
import Testing
@testable import NotchiCore

// Snapshot tests (spec R2 M1, R3 step 2). References live next to this file; NOTCHI_RECORD=1 rewrites them.
// A test fails when more than 0.5% of pixels differ beyond a small tolerance (font rasterising varies a little).

let snapshotsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
let recording = ProcessInfo.processInfo.environment["NOTCHI_RECORD"] == "1"

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
            let kit = try #require(pack.pack.notchi.signKit)
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
            let names = try #require(pack.pack.notchi.accessories?.names)
            #expect(names.count == 12)
            for name in names {
                try assertSnapshot(PetRenderer.render(pack, row: .idle, frame: 0, worn: [name], scale: 0.5), named: "acc-\(s.id)-\(name)")
            }
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
