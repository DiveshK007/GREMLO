import Foundation

/// The Claude Code settings merge for "Connect Claude Code": append-only, never replacing other hooks, safe to run
/// twice; PermissionRequest gets a longer timeout because it waits for the user's answer.
public enum HookSettings {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                         "Notification", "Stop", "StopFailure", "SessionEnd"]
    public static let command = "bash ~/.notchi/notchi-hook.sh"

    public static func isOurs(_ entry: Any) -> Bool {
        guard let e = entry as? [String: Any], let hooks = e["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String) == command }
    }

    /// PermissionRequest waits for the user's answer on a surface (up to 110 s in the script), so it gets a
    /// longer timeout than the default; every other event returns at once.
    public static func entry(_ ev: String) -> [String: Any] {
        var hook: [String: Any] = ["type": "command", "command": command]
        if ev == "PermissionRequest" { hook["timeout"] = 120 }
        return ["hooks": [hook]]
    }

    /// Settings with Notchi's entry appended to each event that lacks it (and an older entry of ours brought up to
    /// date). Everything else is untouched.
    public static func merged(_ settings: [String: Any]) -> [String: Any] {
        var s = settings
        var hooks = s["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            var list = hooks[ev] as? [Any] ?? []
            if let i = list.firstIndex(where: isOurs) {
                if !NSDictionary(dictionary: list[i] as? [String: Any] ?? [:]).isEqual(to: entry(ev)) { list[i] = entry(ev) }
            } else {
                list.append(entry(ev))
            }
            hooks[ev] = list
        }
        s["hooks"] = hooks
        return s
    }

    /// Settings with only Notchi's entries removed; events left empty are dropped.
    public static func unmerged(_ settings: [String: Any]) -> [String: Any] {
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
}
