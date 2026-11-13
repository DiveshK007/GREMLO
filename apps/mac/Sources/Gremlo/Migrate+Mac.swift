import Foundation
import GremloCore
import Security

/// One-time carry-over from before the rename (Notchi to Gremlo). Runs first at launch, before anything reads
/// settings, the device key or the config folder. Each step is skipped once the new home has data.
enum Migrate {
    static func run() {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        // 1. settings (the device key, growth, stars, the Closet live here): copy the old defaults domain once
        let current = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        if (UserDefaults.standard.persistentDomain(forName: current) ?? [:]).isEmpty {
            for old in Legacy.defaultsDomains where old != current {
                guard var d = UserDefaults.standard.persistentDomain(forName: old), !d.isEmpty else { continue }
                if let s = d["skin"] as? String { d["skin"] = Legacy.species(s) }
                UserDefaults.standard.setPersistentDomain(d, forName: current)
                print("migrate: settings carried over from \(old)")
                break
            }
        }
        // 2. ~/.notchi -> ~/.gremlo (hook script, global git hooks); a global hooksPath pointing there follows it
        let oldDir = home.appendingPathComponent(Legacy.configDir), newDir = home.appendingPathComponent(".gremlo")
        if fm.fileExists(atPath: oldDir.path) && !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
            try? fm.removeItem(at: newDir.appendingPathComponent(Legacy.hookScript))  // the new script is installed below
            print("migrate: moved \(oldDir.path) to \(newDir.path)")
        }
        if let hp = git(["config", "--global", "--get", "core.hooksPath"]), (hp as NSString).expandingTildeInPath == oldDir.appendingPathComponent("git-hooks").path {
            _ = git(["config", "--global", "core.hooksPath", newDir.appendingPathComponent("git-hooks").path])
        }
        // 3. Application Support/Notchi -> Gremlo (diary, runs, postcards; the socket is recreated)
        let support = home.appendingPathComponent("Library/Application Support")
        let oldSup = support.appendingPathComponent(Legacy.supportDir), newSup = support.appendingPathComponent("Gremlo")
        if fm.fileExists(atPath: oldSup.path) && !fm.fileExists(atPath: newSup.path) { try? fm.moveItem(at: oldSup, to: newSup) }
        // 4. the phone pairing in the Keychain moves to the new service name
        if Keychain.get() == nil, let old = Keychain.get(service: Legacy.keychainService) {
            Keychain.set(old)
            Keychain.delete(service: Legacy.keychainService)
        }
    }

    private static func git(_ args: [String]) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = ["git"] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
