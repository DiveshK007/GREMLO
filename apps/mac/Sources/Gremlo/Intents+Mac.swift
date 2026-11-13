import AppIntents
import GremloCore

// Shortcuts (R2 §10): Pause for N min, Start focus for N min, Make the pet say, Get status. Each one is the same
// request the CLI sends, answered by Backend.handle, so the same limits apply.

@MainActor func run(_ r: Request) -> Reply { backend.handle(r) }

struct PauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause pets"
    static var description = IntentDescription("Pets go home, lines off, counters frozen.")
    @Parameter(title: "Minutes", default: 30) var minutes: Int
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await run(Request("pause", ["min": "\(max(1, min(minutes, 1440)))"]))
        return .result(dialog: "\(r.text)")
    }
}

struct FocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start focus"
    static var description = IntentDescription("25, 50 or 90 minutes. Lines are off and the pet doesn't earn.")
    @Parameter(title: "Minutes", default: 25) var minutes: Int
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await run(Request("focus", ["min": "\(minutes)"]))
        return .result(dialog: "\(r.text)")
    }
}

struct SayIntent: AppIntent {
    static var title: LocalizedStringResource = "Make the pet say"
    static var description = IntentDescription("Up to 80 characters, tagged \"you\". Once every 10 seconds, never during a screen share.")
    @Parameter(title: "Text") var text: String
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await run(Request("say", ["text": String(text.prefix(Commands.sayMax))]))
        return .result(dialog: "\(r.text)")
    }
}

struct StatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get pet status"
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let r = await run(Request("status"))
        return .result(value: r.text, dialog: "\(r.text)")
    }
}

struct GremloShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PauseIntent(), phrases: ["Pause \(.applicationName)"], shortTitle: "Pause pets", systemImageName: "pause")
        AppShortcut(intent: FocusIntent(), phrases: ["Start focus with \(.applicationName)"], shortTitle: "Start focus", systemImageName: "timer")
        AppShortcut(intent: StatusIntent(), phrases: ["\(.applicationName) status"], shortTitle: "Status", systemImageName: "info.circle")
    }
}
