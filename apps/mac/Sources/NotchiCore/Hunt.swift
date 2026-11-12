import Foundation

// Round 4 §2-10: test runs and the bug hunt, the stuck detector, git moods, the drop zone, dreams, tricks,
// seasons and the meeting heads-up. Everything here runs on the Mac; nothing in this file talks to a network.

// MARK: - Test runs (R4 §2)

public enum TestRun {
    /// A finished Bash test run: true passed, false failed, nil when it isn't a test run (or was interrupted).
    public static func outcome(event: String, tool: String?, command: String?, interrupted: Bool = false, extra: [String] = []) -> Bool? {
        guard tool == "Bash", let c = command, Tools.runner(c, extra: extra) != nil, !interrupted else { return nil }
        switch event {
        case "PostToolUse": return true
        case "PostToolUseFailure": return false
        default: return nil
        }
    }
}

// MARK: - Bug hunt (R4 §2)

public struct Bug: Equatable, Sendable { public let id: Int; public var x: Double }

public struct BugHunt: Sendable {
    public static let maxOnScreen = 3
    public private(set) var bugs: [Bug] = []
    public private(set) var jar: Int
    var nextId = 0
    public init(jar: Int = 0) { self.jar = jar }

    /// A failing run: one bug crawls out, unless three are already out.
    public mutating func failed(at x: Double) -> Bug? {
        guard bugs.count < Self.maxOnScreen else { return nil }
        nextId += 1
        let b = Bug(id: nextId, x: x)
        bugs.append(b)
        return b
    }

    /// A passing run: every bug is caught, nearest to the pet first; each one goes in the jar.
    public mutating func passed(petX: Double) -> [Bug] {
        let eaten = bugs.sorted { abs($0.x - petX) < abs($1.x - petX) }
        jar += eaten.count
        bugs = []
        return eaten
    }

    /// The user squashed it: gone, and it doesn't count in the jar.
    @discardableResult public mutating func squash(_ id: Int) -> Bool {
        guard let i = bugs.firstIndex(where: { $0.id == id }) else { return false }
        bugs.remove(at: i)
        return true
    }

    public mutating func move(_ id: Int, to x: Double) { if let i = bugs.firstIndex(where: { $0.id == id }) { bugs[i].x = x } }

    /// Screen share or the session ended: all bugs leave (none counted).
    public mutating func clear() { bugs = [] }
}

// MARK: - Stuck detector (R4 §3)

public struct StuckTrigger: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case sameError, editRevert }
    public let kind: Kind
    public let count: Int
    public let since: Date
    public let line: String      // the error's first line, or the file name for edit/revert
}

public struct StuckDetector: Sendable {
    public static let repeats = 5, window = 600.0, reverts = 3
    public static let nudge = "You've hit this error 5 times. Explain the cause before trying again."
    var failures: [String: [Date]] = [:]
    var fileHashes: [String: [String]] = [:]
    var fileReverts: [String: (count: Int, since: Date)] = [:]
    public private(set) var ignored = false
    public init() {}

    /// First meaningful line plus the error class, with numbers, hex, paths and timestamps stripped.
    public static func normalise(_ error: String) -> String {
        let lines = error.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.range(of: #"^Exit code \d+$"#, options: .regularExpression) == nil }
        let first = lines.first ?? ""
        let cls = error.range(of: #"\b[A-Z][A-Za-z]*(Error|Exception)\b"#, options: .regularExpression).map { String(error[$0]) } ?? ""
        var s = first
        for (p, r) in [(#"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?Z?"#, "<time>"), (#"(~|\.{0,2})?/[^\s:'\"()]+"#, "<path>"),
                       (#"\b0x[0-9a-fA-F]+\b"#, "<hex>"), (#"\b[0-9a-f]{7,}\b"#, "<hex>"), (#"\d+"#, "<n>")] {
            s = s.replacingOccurrences(of: p, with: r, options: .regularExpression)
        }
        return cls.isEmpty ? s : "\(cls) | \(s)"
    }

    public static func displayLine(_ error: String) -> String {
        error.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0.range(of: #"^Exit code \d+$"#, options: .regularExpression) == nil } ?? ""
    }

    /// A tool failed. Triggers on the 5th identical (normalised) failure within 10 minutes.
    public mutating func failure(tool: String, error: String, at now: Date) -> StuckTrigger? {
        guard !ignored else { return nil }
        let key = tool + "|" + Self.normalise(error)
        let recent = (failures[key] ?? []).filter { now.timeIntervalSince($0) <= Self.window } + [now]
        failures[key] = recent
        guard recent.count >= Self.repeats else { return nil }
        failures[key] = []
        return StuckTrigger(kind: .sameError, count: recent.count, since: recent[0], line: Self.displayLine(error))
    }

    /// A file was edited and now has content `hash`. Going back to an earlier version is a revert; 3 trigger.
    public mutating func edited(file: String, hash: String, at now: Date) -> StuckTrigger? {
        guard !ignored else { return nil }
        let seen = fileHashes[file] ?? []
        guard seen.last != hash else { return nil }  // unchanged (a read before the edit, or a no-op edit)
        fileHashes[file] = Array((seen + [hash]).suffix(20))
        guard seen.dropLast().contains(hash) else { return nil }
        var r = fileReverts[file] ?? (0, now)
        r.count += 1
        fileReverts[file] = r
        guard r.count >= Self.reverts else { return nil }
        fileReverts[file] = nil
        return StuckTrigger(kind: .editRevert, count: r.count, since: r.since, line: (file as NSString).lastPathComponent)
    }

    /// "Ignore this run": quiet until the run ends.
    public mutating func ignoreRun() { ignored = true }
    public mutating func runEnded() { ignored = false; failures = [:]; fileReverts = [:] }

    public static func title(_ t: StuckTrigger, now: Date) -> String {
        let mins = max(1, Int(now.timeIntervalSince(t.since) / 60))
        return t.kind == .sameError ? "Going in circles \u{00B7} same error \(t.count)\u{00D7} \u{00B7} \(mins) min"
            : "Going in circles \u{00B7} \(t.line) reverted \(t.count)\u{00D7} \u{00B7} \(mins) min"
    }
}

// MARK: - Git moods (R4 §4)

public enum GitEvent: String, Sendable, CaseIterable {
    case commit, forcePush = "force-push", tag, merged, conflict

    /// The pack row it plays.
    public var row: Row {
        switch self {
        case .commit: return .greet
        case .forcePush: return .covereyes
        case .tag: return .moonwalk
        case .merged: return .celebrate
        case .conflict: return .tangled
        }
    }

    /// Parses the one line a git hook sends: {"type":"git","event":"<name>","repo":"<hash>"}.
    public static func parse(_ json: [String: Any]) -> GitEvent? {
        guard json["type"] as? String == "git", let e = json["event"] as? String else { return nil }
        return GitEvent(rawValue: e)
    }
}

public enum GitWatch {
    /// The .git directory for a working directory (walking up), or nil.
    public static func gitDir(for dir: String) -> URL? {
        var u = URL(fileURLWithPath: dir).standardized
        while u.path != "/" {
            let g = u.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: g.path, isDirectory: &isDir), isDir.boolValue { return g }
            u.deleteLastPathComponent()
        }
        return nil
    }
    /// A merge is in progress with conflicts to resolve while MERGE_HEAD exists.
    public static func conflicted(_ dir: String) -> Bool {
        gitDir(for: dir).map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("MERGE_HEAD").path) } ?? false
    }
}

/// Installs and removes the git hooks in one repo, chaining any hook already there (it runs first, unchanged).
public enum GitHooks {
    public static let names = ["post-commit", "pre-push", "reference-transaction"]
    public static let marker = "# notchi git hook"
    static let prev = ".notchi-prev"

    public static func install(repo: String, script: URL) throws {
        guard let g = GitWatch.gitDir(for: repo) else { throw NSError(domain: "Notchi", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a git repository"]) }
        try installInto(hooks: g.appendingPathComponent("hooks"), script: script)
    }

    static func installInto(hooks: URL, script: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: hooks, withIntermediateDirectories: true)
        let body = try String(contentsOf: script, encoding: .utf8)
        for n in names {
            let h = hooks.appendingPathComponent(n)
            if let existing = try? String(contentsOf: h, encoding: .utf8), !existing.contains(marker), !fm.fileExists(atPath: h.path + prev) {
                try fm.moveItem(atPath: h.path, toPath: h.path + prev)
            }
            try body.write(to: h, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.path)
        }
    }

    /// `--global`: hooks in core.hooksPath (set to ~/.notchi/git-hooks if unset), chaining what's already there.
    public static func installGlobal(script: URL) throws {
        let dir = globalDir()
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if git(["config", "--global", "--get", "core.hooksPath"]).isEmpty { _ = git(["config", "--global", "core.hooksPath", dir]) }
        try installInto(hooks: URL(fileURLWithPath: dir), script: script)
    }

    public static func removeGlobal() throws {
        let dir = globalDir()
        try removeFrom(hooks: URL(fileURLWithPath: dir))
        if dir == ourGlobal { _ = git(["config", "--global", "--unset", "core.hooksPath"]) }
    }

    static var ourGlobal: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi/git-hooks").path }
    static func globalDir() -> String {
        let set = git(["config", "--global", "--get", "core.hooksPath"])
        return set.isEmpty ? ourGlobal : (set as NSString).expandingTildeInPath
    }
    @discardableResult static func git(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func remove(repo: String) throws {
        guard let g = GitWatch.gitDir(for: repo) else { return }
        try removeFrom(hooks: g.appendingPathComponent("hooks"))
    }

    static func removeFrom(hooks: URL) throws {
        let fm = FileManager.default
        for n in names {
            let h = hooks.appendingPathComponent(n)
            guard let s = try? String(contentsOf: h, encoding: .utf8), s.contains(marker) else { continue }
            try fm.removeItem(at: h)
            if fm.fileExists(atPath: h.path + prev) { try fm.moveItem(atPath: h.path + prev, toPath: h.path) }
        }
    }
}

// MARK: - Drop zone (R4 §5)

public enum DropZone {
    /// File paths one per line, quoted when they contain spaces.
    public static func text(paths: [String]) -> String {
        paths.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: "\n")
    }
    public static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"]
    public static func isImage(_ path: String) -> Bool { imageTypes.contains((path as NSString).pathExtension.lowercased()) }
}

// MARK: - Session steps for the scrubber (R4 §6)

public struct Step: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case read, edit, run, failed, approval, passed }
    public let tool: String
    public let start: Date
    public var end: Date?
    public var kind: Kind
    public let summary: String       // argument summary, stays on the Mac
    public let command: String?      // Bash only: click copies it
    public let file: String?         // file tools: click opens it
    public init(tool: String, start: Date, end: Date? = nil, kind: Kind, summary: String, command: String?, file: String?) {
        self.tool = tool; self.start = start; self.end = end; self.kind = kind; self.summary = summary; self.command = command; self.file = file
    }

    public static func kind(tool: String) -> Kind {
        switch tool {
        case "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch": return .read
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return .edit
        default: return .run
        }
    }
    public static let keepDays = 7.0
}

// MARK: - Dreams (R4 §7)

public enum Dream: String, Sendable { case wrench, flask, bug, merge, check, star, heart, moon }

public struct DreamLog: Codable, Equatable, Sendable {
    public var events: [String] = []           // Dream raw values in the order they happened today
    public var edits = 0, testRuns = 0, testFails = 0, passes = 0, merges = 0, celebrations = 0, approvals = 0
    public init() {}

    public mutating func add(_ d: Dream) {
        switch d {
        case .wrench: edits += 1
        case .flask: testRuns += 1
        case .bug: testFails += 1
        case .merge: merges += 1
        case .check: passes += 1
        case .star: celebrations += 1
        case .heart: approvals += 1
        case .moon: break
        }
        // the bubble shows a sequence, not every edit: collapse repeats
        if events.last != d.rawValue { events = Array((events + [d.rawValue]).suffix(40)) }
    }

    /// One icon per 1.7 s, ending with the moon.
    public var icons: [Dream] { events.compactMap(Dream.init) + [.moon] }

    public func summary(name: String) -> String {
        func n(_ k: Int, _ one: String, _ many: String) -> String { k == 1 ? "one \(one)" : "\(k) \(many)" }
        var parts: [String] = []
        if edits > 0 { parts.append(n(edits, "edit", "edits")) }
        if testFails > 0 { parts.append(n(testFails, "stubborn test", "stubborn tests")) }
        else if passes > 0 { parts.append(n(passes, "passing run", "passing runs")) }
        if parts.isEmpty { return "\(name) is dreaming." }
        return "\(name) is dreaming about \(parts.joined(separator: " and "))."
    }
    public static let interval = 1.7
}

// MARK: - Tricks (R4 §8)

public enum Trick: String, CaseIterable, Sendable {
    case backflip, juggle, moonwalk
    public var requirement: String {
        switch self {
        case .backflip: return "25 approvals answered"
        case .juggle: return "a session with 100 tool calls"
        case .moonwalk: return "the first release tag"
        }
    }
    public static func learned(approvals: Int, maxSessionTools: Int, releaseTags: Int) -> [Trick] {
        var out: [Trick] = []
        if approvals >= 25 { out.append(.backflip) }
        if maxSessionTools >= 100 { out.append(.juggle) }
        if releaseTags >= 1 { out.append(.moonwalk) }
        return out
    }
    /// Shows off on its own at most once an hour, only while idle.
    public static func mayShowOff(last: Date?, now: Date, idle: Bool) -> Bool { idle && (last.map { now.timeIntervalSince($0) >= 3600 } ?? true) }
}

// MARK: - Seasons (R4 §9)

public enum Season: String, Sendable {
    case diwali, winter, october

    /// Diwali (Lakshmi Puja) dates, from published calendars.
    static let diwaliDates: [String] = ["2026-11-08", "2027-10-29", "2028-10-17", "2029-11-05", "2030-10-26", "2031-11-14", "2032-11-02"]
    static let diwaliRegions: Set<String> = ["IN", "NP", "LK", "MU", "FJ", "SG", "MY", "TT", "GY", "SR"]
    static let southern: Set<String> = ["AU", "NZ", "ZA", "AR", "CL", "UY", "PY", "BR", "PE", "BO", "NA", "BW", "LS", "SZ", "MZ", "ZW", "MG"]

    /// Scenery for the date and region; nil most of the year. Diwali shows for 5 days around the day.
    public static func current(_ date: Date, region: String?, calendar: Calendar = Calendar(identifier: .gregorian)) -> Season? {
        let r = region ?? ""
        var cal = calendar
        cal.timeZone = .current
        if diwaliRegions.contains(r) {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = cal; f.timeZone = cal.timeZone
            for s in diwaliDates { if let d = f.date(from: s), abs(cal.dateComponents([.day], from: d, to: cal.startOfDay(for: date)).day ?? 99) <= 2 { return .diwali } }
        }
        let m = cal.component(.month, from: date)
        if m == 10 { return .october }
        let winterMonths: Set<Int> = southern.contains(r) ? [6, 7, 8] : [12, 1, 2]
        return winterMonths.contains(m) ? .winter : nil
    }
    public static let maxSnow = 6
}

// MARK: - Meeting heads-up (R4 §10)

public enum HeadsUp: Equatable, Sendable {
    case none, soon(minutes: Int), inMeeting

    /// Five minutes before: soon (with a countdown); from the start to the end: in the meeting.
    public static func state(start: Date, end: Date, now: Date) -> HeadsUp {
        if now >= start && now < end { return .inMeeting }
        let left = start.timeIntervalSince(now)
        if left > 0 && left <= 300 { return .soon(minutes: Int(ceil(left / 60))) }
        return .none
    }
}

// MARK: - Tolerant decoding

public enum Tolerant {
    /// Decodes `data` over the encoded defaults, so a field added in a later version doesn't wipe saved state.
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T) -> T? {
        guard let base = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))) as? [String: Any],
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let merged = base.merging(saved) { _, s in s }
        guard let d = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(type, from: d)
    }
}

// MARK: - Moments (R2 §15): which line fits what the agent is doing, computed here on the Mac

public enum LineMoment {
    static let deploy = #"\b(deploy|vercel( --prod)?|netlify deploy|fly deploy|kubectl apply|terraform apply|helm (install|upgrade)|wrangler (deploy|publish)|firebase deploy|serverless deploy|eas (build|submit)|cap deploy)\b"#

    /// tests, deploy, long run (over 10 minutes) or any.
    public static func current(command: String?, runSeconds: TimeInterval, extraRunners: [String] = []) -> String {
        if let c = command {
            if Tools.runner(c, extra: extraRunners) != nil { return "tests" }
            if c.range(of: deploy, options: .regularExpression) != nil { return "deploy" }
        }
        return runSeconds > 600 ? "long run" : "any"
    }

    /// The line for this rotation slot: lines tagged for the moment first, then lines tagged "any", then any line.
    public static func pick(order: [Int], tags: [String], moment: String, slot: Int) -> Int? {
        guard !order.isEmpty else { return nil }
        let tag = { (i: Int) in tags.indices.contains(i) ? tags[i] : "any" }
        let exact = order.filter { tag($0) == moment }, anyTagged = order.filter { tag($0) == "any" }
        let pool = !exact.isEmpty ? exact : !anyTagged.isEmpty ? anyTagged : order
        return pool[slot % pool.count]
    }
}

// MARK: - Window perching (spec D §4): a companion stands on its agent's window title bar and follows it

public enum Perch {
    /// Apps an agent runs in. Window bounds need no permission; titles would, so they aren't read.
    public static let agentApps: Set<String> = ["Terminal", "iTerm2", "Ghostty", "Warp", "Alacritty", "kitty", "WezTerm", "Code", "Cursor", "Windsurf", "Zed"]

    public struct Window: Equatable, Sendable { public let owner: String; public let bounds: CGRect; public let layer: Int
        public init(owner: String, bounds: CGRect, layer: Int) { self.owner = owner; self.bounds = bounds; self.layer = layer } }

    /// Agent windows front to back, as Cocoa rects (origin bottom-left of the primary display). Small or
    /// off-screen windows are skipped; full-screen ones too (the pets hide then).
    public static func spots(_ list: [Window], primaryHeight: CGFloat, screen: CGRect) -> [CGRect] {
        list.filter { $0.layer == 0 && agentApps.contains($0.owner) && $0.bounds.width >= 320 && $0.bounds.height >= 160 }
            .map { CGRect(x: $0.bounds.minX, y: primaryHeight - $0.bounds.maxY, width: $0.bounds.width, height: $0.bounds.height) }
            .filter { screen.contains(CGPoint(x: $0.midX, y: $0.maxY - 1)) && !($0.width >= screen.width && $0.height >= screen.height - 40) }
    }
}
