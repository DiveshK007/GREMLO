import Foundation

// Notch Live (spec D §5, R2 §9, R3 §2): which state the notch shows, the approval queue the user answers from it,
// and the usage/cost numbers it shows. No sponsored lines in the notch, ever.

// MARK: - States and priority

public enum LiveState: String, CaseIterable, Sendable {
    case rest, think, peek, ticker, knock, queue, done, room, egg, sleep, visitor, focus, offline
}

public enum NotchLive {
    /// Sizes in points (spec R3 §2; offline from D §5).
    public static func size(_ s: LiveState, agents: Int = 1) -> (w: Double, h: Double) {
        switch s {
        case .rest: return (190, 32)
        case .think: return (210, 32)
        case .peek: return (290, 36)
        case .ticker: return (600, 82)
        case .knock: return (660, 150)
        case .queue: return (700, 60 + 46 * Double(min(max(agents, 2), 4)))
        case .done: return (520, 82)
        case .room: return (540, 230)
        case .egg: return (290, 36)
        case .sleep: return (250, 34)
        case .visitor: return (420, 40)
        case .focus: return (290, 36)
        case .offline: return (360, 36)
        }
    }

    public struct Inputs: Sendable, Equatable {
        public var waiting = 0              // approvals waiting
        public var visitor = false          // a teammate's companion knocking
        public var doneUntil: Date?         // Stop card folds 4 s after Stop
        public var hoverOrPin = false       // ticker on hover or pin
        public var toolRunning = false      // between PreToolUse and its PostToolUse
        public var egg = false              // before hatching
        public var focus = false            // a focus session
        public var thinking = false         // between UserPromptSubmit and the first tool
        public var sleeping = false         // 23:00-06:00 or a nap
        public var offline = false
        public var roomOpen = false         // dragged down
        public init() {}
    }

    /// knock > queue > offline > room > visitor > done > ticker > peek > egg > focus > think > sleep > rest.
    /// Offline sits under approvals (they still work locally) and above everything that needs the network.
    public static func resolve(_ i: Inputs, now: Date) -> LiveState {
        if i.waiting >= 2 { return .queue }
        if i.waiting == 1 { return .knock }
        if i.offline { return .offline }
        if i.roomOpen { return .room }
        if i.visitor { return .visitor }
        if let d = i.doneUntil, now < d { return .done }
        if i.hoverOrPin { return .ticker }
        if i.toolRunning { return .peek }
        if i.egg { return .egg }
        if i.focus { return .focus }
        if i.thinking { return .think }
        if i.sleeping { return .sleep }
        return .rest
    }

    public static let doneHold = 4.0
}

// MARK: - Approvals

public enum Risk {
    /// Commands that delete, push or spend: they get no keyboard shortcut and always need a click.
    static let patterns = [
        #"(^|[\s;&|(])rm\s"#, #"(^|[\s;&|(])rmdir\s"#, #"\bunlink\s"#, #"\bshred\s"#, #"find\s.*-delete\b"#,
        #"\bgit\s+(push|clean|reset\s+--hard|branch\s+-D|tag\s+-d)\b"#, #"\bgh\s+(release|repo\s+delete|pr\s+merge)\b"#,
        #"\b(npm|pnpm|yarn|cargo|gem|twine)\s+publish\b"#, #"\bdocker\s+(push|rm|rmi|system\s+prune)\b"#,
        #"\bkubectl\s+delete\b"#, #"\bterraform\s+(apply|destroy)\b"#, #"(?i)\b(drop|truncate)\s+(table|database)\b"#,
        #"(?i)\bdelete\s+from\b"#, #"\bnear\s+(tokens|contract\s+call-function\s+as-transaction|account\s+delete)\b"#,
        #"\bcast\s+send\b"#, #"(?i)\b(stripe|pay|transfer|withdraw|send-near|send-ft)\b"#, #"\bdd\s+if="#, #"\bmkfs\b"#,
    ]

    public static func isRisky(tool: String, input: [String: Any]) -> Bool {
        if tool == "Bash" || tool == "shell" || tool == "run_terminal_cmd" {
            let cmd = (input["command"] as? String) ?? ""
            return patterns.contains { cmd.range(of: $0, options: .regularExpression) != nil }
        }
        // an MCP or custom tool whose name says it moves money or deletes things
        return tool.range(of: #"(?i)(pay|transfer|send|withdraw|purchase|delete|remove|drop|deploy|publish)"#, options: .regularExpression) != nil
    }
}

public struct ApprovalRequest: Sendable, Equatable, Identifiable {
    public let id: String
    public let session: String
    public let tool: String
    public let summary: String          // what the notch shows; stays on the Mac
    public let risky: Bool
    public let canAlwaysAllow: Bool     // Claude Code suggested an allow rule
    public let received: Date
    public var answeredElsewhere = false

    /// Built from the PermissionRequest hook payload.
    public static func from(id: String, payload: [String: Any], now: Date) -> ApprovalRequest {
        let tool = payload["tool_name"] as? String ?? "tool"
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let text = (input["command"] as? String) ?? (input["file_path"] as? String) ?? (input["url"] as? String)
            ?? (input["pattern"] as? String) ?? (input["description"] as? String) ?? ""
        let summary = String(text.replacingOccurrences(of: "\n", with: " ").prefix(200))
        let suggestions = payload["permission_suggestions"] as? [[String: Any]] ?? []
        let canAlways = suggestions.contains { ($0["type"] as? String) == "addRules" && ($0["behavior"] as? String) == "allow" }
        return ApprovalRequest(id: id, session: payload["session_id"] as? String ?? "", tool: tool, summary: summary,
                               risky: Risk.isRisky(tool: tool, input: input), canAlwaysAllow: canAlways, received: now)
    }
}

public enum Answer: String, Sendable { case allowOnce, alwaysAllow, deny }

public enum Decision {
    /// The PermissionRequest hook output for the user's answer (Claude Code hooks reference).
    /// Always allow passes back Claude Code's own allow-rule suggestions; deny tells Claude it came from the user.
    public static func json(_ a: Answer, suggestions: [[String: Any]]) -> Data {
        var decision: [String: Any]
        switch a {
        case .allowOnce: decision = ["behavior": "allow"]
        case .alwaysAllow:
            let rules = suggestions.filter { ($0["type"] as? String) == "addRules" && ($0["behavior"] as? String) == "allow" }
            decision = ["behavior": "allow"]
            if !rules.isEmpty { decision["updatedPermissions"] = rules }
        case .deny: decision = ["behavior": "deny", "message": "The user denied this from the notch."]
        }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
    }
}

public struct ApprovalQueue: Sendable {
    public private(set) var items: [ApprovalRequest] = []
    public init() {}

    public mutating func add(_ r: ApprovalRequest) { items.append(r); items.sort { $0.received < $1.received } }
    /// Oldest first; only those still waiting.
    public var waiting: [ApprovalRequest] { items.filter { !$0.answeredElsewhere } }
    public var top: ApprovalRequest? { waiting.first }

    /// A keyboard shortcut answers only an ordinary request; risky ones need a click.
    public static func shortcutAllowed(_ r: ApprovalRequest) -> Bool { !r.risky }

    public mutating func remove(_ id: String) { items.removeAll { $0.id == id } }

    /// The agent moved on without us (the user answered in the terminal): the next event for the same session
    /// and tool greys the row out. Returns the ids to release with no decision.
    public mutating func sawEvent(session: String, tool: String?, event: String) -> [String] {
        // PreToolUse comes before the permission check, so only the tool finishing (or the run ending) means
        // someone answered; a false match just falls back to the terminal prompt, which is safe
        let ends = ["Stop", "StopFailure", "SessionEnd"].contains(event)
        guard ends || event == "PostToolUse" else { return [] }
        var released: [String] = []
        for i in items.indices where !items[i].answeredElsewhere && items[i].session == session && (ends || items[i].tool == tool) {
            items[i].answeredElsewhere = true
            released.append(items[i].id)
        }
        return released
    }
}

// MARK: - Usage and cost (spec R2 §9)

public struct Usage: Sendable, Equatable {
    public var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
    public var model: String?
    public init() {}
    public var total: Int { input + output + cacheWrite + cacheRead }
    public static func + (a: Usage, b: Usage) -> Usage {
        var u = Usage()
        u.input = a.input + b.input; u.output = a.output + b.output
        u.cacheWrite = a.cacheWrite + b.cacheWrite; u.cacheRead = a.cacheRead + b.cacheRead
        u.model = b.model ?? a.model
        return u
    }
}

public enum Prices {
    /// Cents per million tokens: input, output, cache write (5 min, 1.25x input), cache read. Anthropic first-party
    /// rates as of 2026-11-03; an estimate, always labelled "est". Unknown models have no price (shown as a dash).
    public static let asOf = "2026-11-03"
    public static let table: [(prefix: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int)] = [
        ("claude-fable-5-2", 800, 4000, 1000, 20), ("claude-mythos-5-2", 800, 4000, 1000, 20),
        ("claude-fable-5-1", 1000, 5000, 1250, 100), ("claude-mythos-5-1", 1000, 5000, 1250, 100), ("claude-fable-5", 1000, 5000, 1250, 100),
        ("claude-opus-5-5", 400, 2000, 500, 20), ("claude-opus-5", 500, 2500, 625, 50),
        ("claude-opus-4-8", 500, 2500, 625, 50), ("claude-opus-4-7", 500, 2500, 625, 50), ("claude-opus-4-6", 500, 2500, 625, 50),
        ("claude-sonnet-5-5", 200, 1000, 250, 10), ("claude-sonnet-5", 200, 1000, 250, 20), ("claude-sonnet-4-6", 300, 1500, 375, 30),
        ("claude-haiku-5-5", 10, 50, 13, 1), ("claude-haiku-4-5", 100, 500, 125, 10),
    ]

    /// Longest matching prefix, so "claude-opus-5-5[1m]" is Opus 5.5 and not Opus 5.
    public static func entry(_ model: String) -> (prefix: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int)? {
        table.filter { model.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }
    }

    /// Estimated cost in hundred-millionths of a dollar (cents x 1e-6), integer; nil without a known model.
    public static func costMicroCents(_ u: Usage) -> Int? {
        guard let m = u.model, let p = entry(m) else { return nil }
        return u.input * p.input + u.output * p.output + u.cacheWrite * p.cacheWrite + u.cacheRead * p.cacheRead
    }

    /// "$0.42 est", or a dash when unknown. Never $0.00 for missing data.
    public static func label(_ u: Usage?) -> String {
        guard let u, u.total > 0, let mc = costMicroCents(u) else { return "\u{2014}" }
        let cents = Double(mc) / 1_000_000
        return String(format: "$%.2f est", cents / 100)
    }
}

/// Reads a Claude Code transcript (JSONL) incrementally: call `feed` with each new chunk; it keeps a partial line.
public struct TranscriptUsageReader: Sendable {
    var partial = ""
    public private(set) var usage = Usage()
    public init() {}

    public mutating func feed(_ chunk: String) {
        let text = partial + chunk
        var lines = text.components(separatedBy: "\n")
        partial = lines.removeLast()
        for line in lines where line.contains("\"usage\"") {
            guard let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = obj["message"] as? [String: Any], let u = msg["usage"] as? [String: Any] else { continue }
            var add = Usage()
            add.input = u["input_tokens"] as? Int ?? 0
            add.output = u["output_tokens"] as? Int ?? 0
            add.cacheWrite = u["cache_creation_input_tokens"] as? Int ?? 0
            add.cacheRead = u["cache_read_input_tokens"] as? Int ?? 0
            add.model = msg["model"] as? String
            usage = usage + add
        }
    }
}

/// Soft alerts at user-set amounts (cents) per run and per day: an amber pulse, never a block.
public enum SoftAlert {
    public static func due(costMicroCents: Int?, limitCents: Int?) -> Bool {
        guard let c = costMicroCents, let l = limitCents, l > 0 else { return false }
        return c >= l * 1_000_000
    }
}
