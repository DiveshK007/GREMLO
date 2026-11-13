import Foundation
import Testing
@testable import GremloCore

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

@Suite struct LegacyTests {
    @Test func anInstallFromBeforeTheRenameIsUpgradedInPlace() {
        let mine: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"]]]
        let old: [String: Any] = ["hooks": ["Stop": [mine, ["hooks": [["type": "command", "command": Legacy.hookCommand]]]],
                                            "PreToolUse": [["hooks": [["type": "command", "command": Legacy.hookCommand]]], HookSettings.entry("PreToolUse")]]]
        let up = HookSettings.merged(old)["hooks"] as? [String: Any] ?? [:]
        let stop = up["Stop"] as? [Any] ?? []
        #expect(stop.count == 2 && !HookSettings.isOurs(stop[0]), "the user's hook stays")
        #expect(NSDictionary(dictionary: stop[1] as? [String: Any] ?? [:]).isEqual(to: HookSettings.entry("Stop")), "the old entry became the new one")
        #expect((up["PreToolUse"] as? [Any])?.count == 1, "old and new side by side: one is kept")
        let text = String(decoding: (try? JSONSerialization.data(withJSONObject: up)) ?? Data(), as: UTF8.self)
        #expect(!text.contains(Legacy.configDir), "no old command left")
        #expect(HookSettings.unmerged(["hooks": ["Stop": [["hooks": [["type": "command", "command": Legacy.hookCommand]]]]]])["hooks"] == nil)
    }

    @Test func oldPacksSpeciesAndPairingCodesStillRead() throws {
        let pets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../assets/pets/gremlo/pet.json").standardized
        let json = try String(contentsOf: pets, encoding: .utf8).replacingOccurrences(of: "\"gremlo\": {", with: "\"\(Legacy.packKey)\": {")
        #expect(json.contains("\"\(Legacy.packKey)\": {"))
        #expect(try Pack.decode(Data(json.utf8)).gremlo.rows.count == 39, "a pack made before the rename loads")
        #expect(Legacy.species("notchi") == "gremlo" && Legacy.species("notchi-pip") == "gremlo-pip" && Legacy.species("gremlo-moss") == "gremlo-moss")
        let p = PhonePairing.new(relay: "https://r.example")
        let oldCode = p.code.replacingOccurrences(of: "gremlo-pair:", with: "notchi-pair:")
        #expect(PhonePairing.from(code: oldCode) == p)
    }
}
