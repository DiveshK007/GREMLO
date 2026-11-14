import CoreGraphics
import Testing
@testable import GremloCore

@Suite struct HomePathTests {
    let sprite = CGSize(width: 192 * 2.0 / 7, height: 208 * 2.0 / 7)  // the v6 cell at the app's scale
    let foot = CGFloat(208 - 194) * 2 / 7

    /// (screen, visibleFrame, door centre): a 14" notched MacBook with the Dock at the bottom (this Mac's numbers),
    /// a 16" notched one with the Dock hidden, and a plain display with the Dock on the right.
    var screens: [(CGRect, CGRect, CGFloat)] {
        [(CGRect(x: 0, y: 0, width: 1470, height: 956), CGRect(x: 0, y: 54, width: 1470, height: 869), 735),
         (CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 0, y: 0, width: 1728, height: 1080), 864),
         (CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 1850, height: 1055), 960)]
    }

    @Test func everyPointOnTheWayHomeKeepsThePetOnScreenAndBelowTheMenuBar() {
        for (screen, visible, door) in screens {
            let h = HomePath(screen: screen, visible: visible, sprite: sprite, footPadding: foot)
            for start in [visible.minX, visible.midX, h.wallX] {
                let pts = h.points(startX: start, doorCenterX: door)
                #expect(pts.count > 100)
                for p in pts {
                    #expect(h.keepsInside(p), "sprite at \(p) leaves the screen or goes under the menu bar on \(screen.size)")
                }
            }
            #expect(h.points(startX: 0, doorCenterX: door).last?.x == h.doorX(doorCenterX: door), "ends under the door")
        }
    }

    @Test func theOldCeilingWentIntoTheMenuBarBand() {
        let (screen, visible, _) = screens[0]
        let h = HomePath(screen: screen, visible: visible, sprite: sprite, footPadding: foot)
        #expect(!h.keepsInside(CGPoint(x: h.wallX, y: h.ceilingY + foot)), "lifted by footPadding, its top sat in the band")
        #expect(h.keepsInside(CGPoint(x: h.wallX, y: h.ceilingY)))
    }

    @Test func wallsNeverPassTheScreenEdgeEvenOnAWindow() {
        let (screen, visible, door) = screens[0]
        let h = HomePath(screen: screen, visible: visible, sprite: sprite, footPadding: foot)
        let past = h.walls(perch: CGRect(x: 1200, y: 400, width: 900, height: 300))  // a window hanging off the right edge
        #expect(past.right == h.wallX && past.left == 1200)
        let inside = h.walls(perch: CGRect(x: 100, y: 400, width: 600, height: 300))
        #expect(inside.left == 100 && inside.right == 700 - sprite.width)
        #expect(h.doorX(doorCenterX: 99_999) == h.wallX && h.doorX(doorCenterX: -50) == h.leftX && h.doorX(doorCenterX: door) == door - sprite.width / 2)
    }
}
