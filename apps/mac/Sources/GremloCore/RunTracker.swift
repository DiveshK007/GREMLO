import Foundation

/// What the current run is doing, for the ticker and the done card. Counts and times only; nothing leaves the Mac.
public final class RunTracker {
    public var thinking = false, toolRunning = false
    public var started: Date?, endedAt: Date?, doneUntil: Date?, lastToolEnd: Date?
    public var tools = 0, errors = 0, approvalsAtStart = 0
    public var lastTool = ""
    public var agent = "Claude Code"
    public var activity: [Character] = []   // r read, e edit, x run, f failed, a approval, p passed
    public var steps: [Step] = []           // the scrubber's data (R4 §6), saved for 7 days on Stop
    public private(set) var reader = TranscriptUsageReader()
    /// The transcript's usage when this run's prompt came in; nil until a prompt is seen (the app started mid-run).
    public private(set) var runBase: Usage?
    /// Usage of this run only (since its UserPromptSubmit), never the whole session's transcript. nil when unknown.
    public var runUsage: Usage? { runBase.map { reader.usage.since($0) } }
    /// Called with the steps when a run ends (the app saves them for the scrubber).
    public var onEnd: (([Step]) -> Void)?
    public init() {}
    /// Estimated spend today across runs (micro-cents), for the per-day soft alert. Local only.
    public var dayMicroCents = 0
    private var day = Calendar.current.startOfDay(for: Date())
    private var transcript: String?
    private var offset: UInt64 = 0

    public func event(_ hook: [String: Any], approvalsAnswered: Int) {
        let ev = hook["hook_event_name"] as? String ?? ""
        let tool = hook["tool_name"] as? String
        if let path = hook["transcript_path"] as? String, path != transcript { transcript = path; offset = 0; reader = TranscriptUsageReader(); runBase = nil }
        switch ev {
        case "UserPromptSubmit":
            started = Date(); endedAt = nil; doneUntil = nil; lastToolEnd = nil; tools = 0; errors = 0; activity = []; steps = []
            thinking = true; approvalsAtStart = approvalsAnswered
            tail(); runBase = reader.usage  // everything before this prompt belongs to earlier runs
        case "PreToolUse":
            thinking = false; toolRunning = true; tools += 1; lastTool = tool ?? ""
            let input = hook["tool_input"] as? [String: Any] ?? [:]
            let summary = (input["command"] as? String) ?? (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
                ?? (input["pattern"] as? String) ?? (input["url"] as? String) ?? ""
            steps.append(Step(tool: tool ?? "tool", start: Date(), kind: Step.kind(tool: tool ?? ""), summary: String(summary.prefix(80)),
                              command: input["command"] as? String, file: input["file_path"] as? String))
            mark(Tools.prop(tool: tool ?? "", command: (hook["tool_input"] as? [String: Any])?["command"] as? String))
        case "PostToolUse", "PostToolUseFailure":
            toolRunning = false; lastToolEnd = Date()
            if let i = steps.lastIndex(where: { $0.tool == (tool ?? "") && $0.end == nil }) {
                steps[i].end = Date()
                let cmd = (hook["tool_input"] as? [String: Any])?["command"] as? String
                if ev == "PostToolUseFailure" { steps[i].kind = .failed; push("f") }
                else if TestRun.outcome(event: ev, tool: tool, command: cmd) == true { steps[i].kind = .passed }
            }
        case "PermissionRequest":
            push("a")
            steps.append(Step(tool: tool ?? "tool", start: Date(), end: Date(), kind: .approval, summary: "approval", command: nil, file: nil))
        case "Stop", "StopFailure":
            thinking = false; toolRunning = false; endedAt = Date()
            if ev == "StopFailure" { errors += 1; push("f") } else { push("p") }
            doneUntil = Date().addingTimeInterval(NotchLive.doneHold)
            onEnd?(steps)
        default: break
        }
        tail()
    }

    private func mark(_ p: Prop?) {
        switch p {
        case .magnifier, .globe: push("r")
        case .wrench, .notepad: push("e")
        default: push("x")
        }
    }
    private func push(_ c: Character) { activity.append(c); if activity.count > 48 { activity.removeFirst(activity.count - 48) } }

    /// Reads only the new bytes of the transcript since last time.
    public func tail() {
        guard let path = transcript, let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < offset { offset = 0; reader = TranscriptUsageReader(); runBase = runBase.map { _ in Usage() } }
        try? h.seek(toOffset: offset)
        let data = (try? h.readToEnd()) ?? Data()
        offset += UInt64(data.count)
        let before = Prices.costMicroCents(reader.usage) ?? 0
        reader.feed(String(decoding: data, as: UTF8.self))
        let today = Calendar.current.startOfDay(for: Date())
        if today != day { day = today; dayMicroCents = 0 }
        dayMicroCents += max(0, (Prices.costMicroCents(reader.usage) ?? 0) - before)
    }

    public var elapsed: TimeInterval { started.map { (endedAt ?? Date()).timeIntervalSince($0) } ?? 0 }
}
