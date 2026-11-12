import Foundation
import Testing
@testable import NotchiCore

@Suite struct HookSettingsTests {
    @Test func mergeKeepsTheUsersHooksAndIsIdempotent() {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"]]]
        let start: [String: Any] = ["model": "opus", "hooks": ["Stop": [other]]]
        let once = HookSettings.merged(start), twice = HookSettings.merged(once)
        let stop = (once["hooks"] as? [String: Any])?["Stop"] as? [Any] ?? []
        #expect(stop.count == 2 && !HookSettings.isOurs(stop[0]) && HookSettings.isOurs(stop[1]), "the user's hook stays first, ours is appended")
        #expect(NSDictionary(dictionary: once).isEqual(to: twice), "connecting twice changes nothing")
        #expect(once["model"] as? String == "opus", "other settings untouched")
        #expect(NSDictionary(dictionary: HookSettings.unmerged(once)).isEqual(to: start), "disconnect removes only our entries")
        for ev in HookSettings.events { #expect(((once["hooks"] as? [String: Any])?[ev] as? [Any])?.contains(where: HookSettings.isOurs) == true, "\(ev)") }
    }

    @Test func permissionRequestWaitsAndOldEntriesAreUpgradedInPlace() {
        let once = HookSettings.merged([:])
        let perm = ((once["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
        #expect(perm?.first?["timeout"] as? Int == 120)
        let stop = ((once["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
        #expect(stop?.first?["timeout"] == nil, "every other event returns at once")
        let old: [String: Any] = ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": HookSettings.command]]]]]]
        let upgraded = ((HookSettings.merged(old)["hooks"] as? [String: Any])?["PermissionRequest"] as? [Any]) ?? []
        #expect(upgraded.count == 1, "upgraded in place, not duplicated")
        #expect(NSDictionary(dictionary: upgraded[0] as? [String: Any] ?? [:]).isEqual(to: HookSettings.entry("PermissionRequest")))
    }
}
