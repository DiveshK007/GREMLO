import CoreGraphics
import Foundation
import Testing
@testable import NotchiCore

@Suite struct Colours {
    @Test func everyAccentPassesOnInkAndItsPaperShadePassesOnPaper() {
        let ink = RGB(hex: Palette.ink)!, paper = RGB(hex: Palette.paper)!
        for s in Roster.all {
            let accent = RGB(hex: s.accent)!, safe = RGB(hex: s.paperSafe)!
            #expect(RGB.contrast(accent, ink) >= 4.5, "\(s.name) accent on ink")
            #expect(RGB.contrast(ink, accent) >= 4.5, "ink text on a \(s.name) button")
            #expect(RGB.contrast(safe, paper) >= 4.5, "\(s.name) paper-safe text on paper")
        }
        // the spec's corrected figure: Notchi's accent on ink is 6.4:1, not 7.4
        #expect(abs(RGB.contrast(RGB(hex: "#FF5A3C")!, ink) - 6.4) < 0.1)
    }

    @Test func rosterHasEightSpeciesThreeStartersNoPrices() {
        #expect(Roster.all.count == 8)
        #expect(Roster.all.filter(\.starter).map(\.name) == ["Notchi", "Pip", "Moss"])
        for s in Roster.all { #expect(!s.unlock.contains("$") && !s.unlock.lowercased().contains("buy"), "\(s.name) never for sale") }
        #expect(Set(Roster.all.map(\.id)).count == 8)
    }
}

@Suite struct Timing {
    @Test func moodScalesRateNeverFrames() {
        #expect(Rates.fps(.walk, mood: "thriving") == 10)
        #expect(Rates.fps(.walk, mood: "stable") == 8)
        #expect(abs(Rates.fps(.walk, mood: "hungry")! - 4.8) < 1e-9)
        #expect(Rates.fps(.gaze, mood: "stable") == nil, "gaze is picked by the cursor, not a clock")
        #expect(Sequence.frames(.walk, count: 8, mood: "hungry") == Array(0..<8))
    }

    @Test func idleRowFramesByMoodAndAnnoyByClicks() {
        #expect(Sequence.frames(.idle, count: 8) == [0, 1, 2, 3])
        #expect(Sequence.frames(.idle, count: 8, mood: "hungry") == [4])
        #expect(Sequence.frames(.idle, count: 8, mood: "asleep") == [5, 6])
        #expect(Sequence.frames(.idle, count: 3) == [0, 1, 2], "an older 3-frame idle just loops")
        #expect(Sequence.frames(.annoy, count: 6, clicks: 1) == [0])
        #expect(Sequence.frames(.annoy, count: 6, clicks: 4) == [1, 2])
        #expect(Sequence.frames(.annoy, count: 6, clicks: 7) == [3, 4, 5])
    }

    @Test func backflipArcPeaksAt1point6BodyHeightsHalfwayThrough() throws {
        let body: CGFloat = 100
        #expect(Arcs.backflipLift(t: 0, bodyHeight: body) == 0)
        #expect(Arcs.backflipLift(t: 0.5, bodyHeight: body) == 0)
        #expect(abs(Arcs.backflipLift(t: 0.25, bodyHeight: body) - 160) < 1e-9)
        #expect(Arcs.backflipLift(t: 0.1, bodyHeight: body) < Arcs.backflipLift(t: 0.2, bodyHeight: body))
        let pip = try realPack("notchi-pip")
        #expect(Arcs.bodyHeight(pip) == CGFloat(194 - pip.head(.idle, frame: 0)!.y))
    }

    @Test func moonwalkSlidesAgainstTheWayItFaces() {
        #expect(Arcs.moonwalkVelocity(facing: 1, walkPointsPerSecond: 24) == -24)
        #expect(Arcs.moonwalkVelocity(facing: -1, walkPointsPerSecond: 24) == 24)
    }
}

@Suite struct PlateGeometry {
    let kit = SignKit(path: "signkit.png", size: [20, 11], slice: .init(top: 3, right: 4, bottom: 3, left: 4))

    @Test func kitPixelIsWholeAndAtLeastThree() {
        #expect(Plate.kitPx(scale: 2.0 / 7) == 3)
        #expect(Plate.kitPx(scale: 1) == 7)
        #expect(Plate.kitPx(scale: 0.5) == 4)
        #expect(Plate.kitPx(scale: 0.1) == 3)
        #expect(abs(Plate.fontSize(kitPx: 3) - 11.1) < 1e-9, "3.7 kit px: 11 px at real size")
    }

    @Test func plateStretchesForLongLinesAndNeverShrinksBelowTheKit() {
        let short = Plate.layout(textWidth: 0, kit: kit, scale: 2.0 / 7)
        #expect(short.size == CGSize(width: 60, height: 33), "the 20 x 11 kit at 3 pt per kit px")
        let long = Plate.layout(textWidth: 300, kit: kit, scale: 2.0 / 7)
        #expect(long.size.height == 33)
        #expect(long.size.width >= 300 + 8 * 3, "slices plus the whole line: never truncated")
        #expect(long.textRect.width == 300)
        #expect(long.adTab.maxX == long.size.width, "the AD tab sits on the top-right corner")
    }

    @Test func plateBottomCentreSitsOnTheAnchorAndNeverMirrors() throws {
        let pip = try realPack("notchi-pip")
        let g = PetGeometry(cellW: 192, cellH: 208, scale: 0.5)
        let plate = Plate.layout(textWidth: 100, kit: kit, scale: 0.5)
        let r = Plate.frame(plate, pack: pip, frame: 0, geometry: g, flipped: false)!
        let a = pip.plateAnchor(frame: 0)!
        #expect(abs(r.midX - CGFloat(a.x) * 0.5) <= 0.5)
        #expect(r.minY == (CGFloat(208 - a.y) * 0.5).rounded())
        let f = Plate.frame(plate, pack: pip, frame: 0, geometry: g, flipped: true)!
        #expect(f.size == r.size, "flipping moves the anchor, never the plate's shape")
        #expect(abs(f.midX - (192 - CGFloat(a.x)) * 0.5) <= 0.5)
    }
}

@Suite struct AccessoryGeometry {
    @Test func anchorPointLandsOnTheHeadAndMirrorsWithTheSprite() throws {
        let p = try realPack("notchi")
        let sheet = p.notchi.accessories!
        let g = PetGeometry(cellW: 192, cellH: 208, scale: 1)
        let h = p.head(.idle, frame: 0)!
        let r = Accessories.frame(sheet: sheet, pack: p, row: .idle, frame: 0, geometry: g, flipped: false)!
        // the accessory's anchor (20, 12) in its own units, scaled by unitPx, must land on headAnchor
        #expect(abs(r.minX + 20 * CGFloat(h.unitPx) - CGFloat(h.x)) < 1e-9)
        #expect(abs(r.maxY - 12 * CGFloat(h.unitPx) - CGFloat(208 - h.y)) < 1e-9)
        #expect(r.width == 40 * CGFloat(h.unitPx))
        let m = Accessories.frame(sheet: sheet, pack: p, row: .idle, frame: 0, geometry: g, flipped: true)!
        #expect(abs((m.minX + m.maxX) / 2 - (192 - (r.minX + r.maxX) / 2)) < 1e-9, "mirrored about the cell centre")
        #expect(Accessories.frame(sheet: sheet, pack: p, row: .climb, frame: 0, geometry: g, flipped: false) == nil)
    }

    @Test func drawOrderIsNeckFaceHeadOnePerSlot() {
        #expect(Accessories.drawOrder(["crown", "glasses", "scarf"]) == ["scarf", "glasses", "crown"])
        #expect(Accessories.drawOrder(["beanie", "crown"]) == ["crown"], "one item per slot; the later choice wins")
        #expect(Slot.of("shades") == .face && Slot.of("scarf") == .neck && Slot.of("wizard") == .head)
    }
}
