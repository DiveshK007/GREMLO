import Foundation

/// One-click "Connect Claude Code": installs Notchi's hook into ~/.claude/settings.json the same way
/// scripts/install-hooks.sh does: append-only, never replacing other hooks, safe to run twice, backed up first.
enum ClaudeHooks {
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                         "Notification", "Stop", "StopFailure", "SessionEnd"]
    static let command = "bash ~/.notchi/notchi-hook.sh"
    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static var scriptURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi/notchi-hook.sh") }

    static func isOurs(_ entry: Any) -> Bool {
        guard let e = entry as? [String: Any], let hooks = e["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String) == command }
    }

    /// Settings with Notchi's entry appended to each event that lacks it. Everything else is untouched.
    static func merged(_ settings: [String: Any]) -> [String: Any] {
        var s = settings
        var hooks = s["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            var list = hooks[ev] as? [Any] ?? []
            if !list.contains(where: isOurs) { list.append(["hooks": [["type": "command", "command": command]]]) }
            hooks[ev] = list
        }
        s["hooks"] = hooks
        return s
    }

    /// Settings with only Notchi's entries removed; events left empty are dropped.
    static func unmerged(_ settings: [String: Any]) -> [String: Any] {
        var s = settings
        guard var hooks = s["hooks"] as? [String: Any] else { return s }
        for (ev, value) in hooks {
            guard let list = value as? [Any] else { continue }
            let kept = list.filter { !isOurs($0) }
            if kept.isEmpty { hooks.removeValue(forKey: ev) } else { hooks[ev] = kept }
        }
        if hooks.isEmpty { s.removeValue(forKey: "hooks") } else { s["hooks"] = hooks }
        return s
    }

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
        guard let bundled = Bundle.module.url(forResource: "notchi-hook", withExtension: "sh") else {
            throw NSError(domain: "Notchi", code: 2, userInfo: [NSLocalizedDescriptionKey: "hook script missing from the app"])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: scriptURL)
        try fm.copyItem(at: bundled, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try write(merged(try read()))
    }

    static func disconnect() throws {
        try write(unmerged(try read()))
    }

    /// Self-check of the merge rules, run once at launch in debug builds.
    static func selfCheck() {
        let other: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"]]]
        let start: [String: Any] = ["model": "opus", "hooks": ["Stop": [other]]]
        let once = merged(start), twice = merged(once)
        let stop = (once["hooks"] as? [String: Any])?["Stop"] as? [Any] ?? []
        assert(stop.count == 2 && !isOurs(stop[0]) && isOurs(stop[1]), "merge keeps the user's hook and appends ours")
        assert(NSDictionary(dictionary: once).isEqual(to: twice), "connecting twice changes nothing")
        assert((once["model"] as? String) == "opus", "other settings untouched")
        let back = unmerged(once)
        assert(NSDictionary(dictionary: back).isEqual(to: start), "disconnect removes only Notchi's entries")
    }
}
