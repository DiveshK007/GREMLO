import Foundation
import NotchiCore

/// One-click "Connect Claude Code": installs Notchi's hook into ~/.claude/settings.json the same way
/// scripts/install-hooks.sh does: append-only, never replacing other hooks, safe to run twice, backed up first.
enum ClaudeHooks {
    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static var scriptURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi/notchi-hook.sh") }
    static var events: [String] { HookSettings.events }
    static func isOurs(_ e: Any) -> Bool { HookSettings.isOurs(e) }
    static func merged(_ s: [String: Any]) -> [String: Any] { HookSettings.merged(s) }
    static func unmerged(_ s: [String: Any]) -> [String: Any] { HookSettings.unmerged(s) }

    static func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] } // no file yet: start empty
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Notchi", code: 1, userInfo: [NSLocalizedDescriptionKey: "~/.claude/settings.json is not a JSON object; left untouched"])
        }
        return obj
    }

    static var isConnected: Bool {
        guard let s = try? read(), let hooks = s["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ((hooks[$0] as? [Any]) ?? []).contains(where: isOurs) }
    }

    /// Backup, then an atomic write, so a crash can never leave Claude Code with a broken settings file.
    static func write(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.notchi-backup.json")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    static func connect() throws {
        // The .app ships it in Contents/Resources; Bundle.module (swift run) is touched only when that's absent,
        // because its accessor crashes when its bundle isn't next to the executable.
        guard let bundled = Bundle.main.url(forResource: "notchi-hook", withExtension: "sh") ?? Bundle.module.url(forResource: "notchi-hook", withExtension: "sh") else {
            throw NSError(domain: "Notchi", code: 2, userInfo: [NSLocalizedDescriptionKey: "hook script missing from the app"])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: scriptURL)
        try fm.copyItem(at: bundled, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try write(merged(try read()))
    }

    /// An app update can change the hook script; when connected, keep the installed copy identical to ours.
    static func refreshScriptIfStale() {
        guard isConnected, let bundled = Bundle.main.url(forResource: "notchi-hook", withExtension: "sh") ?? Bundle.module.url(forResource: "notchi-hook", withExtension: "sh"),
              let want = try? Data(contentsOf: bundled), (try? Data(contentsOf: scriptURL)) != want else { return }
        try? want.write(to: scriptURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try? write(merged(try read()))  // also brings the PermissionRequest timeout up to date
        print("hook script updated in \(scriptURL.path)")
    }

    static func disconnect() throws {
        try write(unmerged(try read()))
    }
}
