import CoreGraphics
import Testing
@testable import GremloCore

struct ScreenShareTests {
    // what the window list held on macOS 27.2 (1470 pt wide), idle and during a 3 s recording
    func win(_ owner: String, _ layer: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> [String: Any] {
        [kCGWindowOwnerName as String: owner, kCGWindowLayer as String: layer, kCGWindowBounds as String: ["X": x, "Y": y, "Width": w, "Height": h]]
    }
    var idle: [[String: Any]] { [win("MenuBarAgent", 25, 0, 0, 1470, 33), win("Window Server", 24, 0, 0, 1470, 33), win("Screenshot", 24, 0, 0, 1470, 956)] }

    @Test func idleScreenIsNotShared() {
        #expect(!ScreenShare.indicatorShowing(idle, screenWidth: 1470), "the Screenshot app's leftover full-screen window is not a recording")
    }

    @Test func recordingShowsTheIndicator() {
        let rec = idle + [win("Window Server", 2147483630, 545, 911, 28, 40), win("Window Server", 2147483630, 1443, 1, 28, 28)]
        #expect(ScreenShare.indicatorShowing(rec, screenWidth: 1470))
        #expect(!ScreenShare.indicatorShowing(idle + [win("Window Server", 2147483630, 545, 911, 28, 40)], screenWidth: 1470),
                "a high window that isn't in the menu bar's right end is not the indicator")
        #expect(!ScreenShare.indicatorShowing(idle + [win("SomeApp", 2147483630, 1443, 1, 28, 28)], screenWidth: 1470), "only the window server's own")
    }
}
