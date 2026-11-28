import AppKit
import Sparkle

// Auto-update (Sparkle). Only release builds carry a feed (SUFeedURL and SUPublicEDKey in Info.plist, set by
// release-mac.sh); a build from source has none, so there is no updater and it updates by running install.sh again.
// Every update is checked against the EdDSA key in the app before it is installed.
final class Updates {
    static let shared = Updates()
    private let controller: SPUStandardUpdaterController?

    private init() {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        controller = feed?.isEmpty == false && key?.isEmpty == false
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
    }

    var available: Bool { controller != nil }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "source build" }

    /// On by default (Info.plist); the Settings toggle turns checking and installing on or off together.
    var automatic: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func check() {
        NSApp.activate(ignoringOtherApps: true)  // a menu bar app: bring Sparkle's window to the front
        controller?.checkForUpdates(nil)
    }
}

extension Backend {
    @objc func checkForUpdates() { menu.dismiss(); Updates.shared.check() }
    @objc func toggleAutoUpdate(_ b: NSButton) { Updates.shared.automatic = b.state == .on; settings.reload() }

    func updatesGroup() -> NSView {
        let w = pageWidth
        let u = Updates.shared
        guard u.available else {
            return UI.group("Updates", [UI.row("Version \(u.version)", "Built from source: run the install line again to update.", nil, width: w)], width: w)
        }
        return UI.group("Updates", [
            UI.row("Update automatically", "Checks once a day and installs signed updates when you next quit or restart.",
                   Toggle(on: u.automatic, target: self, action: #selector(toggleAutoUpdate(_:)), label: "Update automatically"), width: w),
            UI.row("Version \(u.version)", nil, Btn("Check now", target: self, action: #selector(checkForUpdates)), width: w),
        ], width: w)
    }
}
