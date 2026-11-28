import CoreGraphics

// Whether the screen is being recorded or shared, from the window list. Checked on macOS 27.2: while an app records the
// screen (QuickTime, the Screenshot toolbar, a capture tool) the window server shows the privacy indicator, a 28 x 28 pt
// window at the right end of the menu bar, far above every normal level. Idle, it isn't there. The microphone and camera
// light the same indicator, so a share during a call reads as the call (the pet sleeps). The Screenshot app
// (screencaptureui) keeps a full-screen window up for hours after a screenshot, so it proves nothing.

public enum ScreenShare {
    /// The indicator is up. The microphone and camera light it too, so callers rule those out. The window server is
    /// known by the owner name the window list gives it: an app can't read its process name (it runs as another user).
    public static func indicatorShowing(_ windows: [[String: Any]], screenWidth: Double) -> Bool {
        windows.contains { w in
            guard w[kCGWindowOwnerName as String] as? String == "Window Server",
                  let layer = w[kCGWindowLayer as String] as? Int, layer > Int(CGWindowLevelForKey(.screenSaverWindow)),
                  let b = w[kCGWindowBounds as String] as? [String: Any],
                  let x = (b["X"] as? Double) ?? (b["X"] as? Int).map(Double.init), let y = (b["Y"] as? Double) ?? (b["Y"] as? Int).map(Double.init),
                  let wd = (b["Width"] as? Double) ?? (b["Width"] as? Int).map(Double.init), let h = (b["Height"] as? Double) ?? (b["Height"] as? Int).map(Double.init)
            else { return false }
            return wd <= 48 && h <= 48 && y <= 8 && x >= screenWidth - 240  // a dot in the menu bar's right end
        }
    }
}
