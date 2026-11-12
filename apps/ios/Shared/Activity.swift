#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// The Live Activity while an agent runs: eyes and a timer, expanding to ask when something needs approval.
struct RunAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mood: String
        var tools: Int
        var waitingId: String?
        var waitingTool: String?
        var waitingSummary: String?
        var waitingRisky: Bool
        var waitingCount: Int
    }
    var name: String
    var species: String
    var startedAt: Date
}

/// Allow or deny from the lock screen or the Dynamic Island. Allowing asks for Face ID first.
struct AnswerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Answer approval"
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Request") var id: String
    @Parameter(title: "Allow") var allow: Bool
    init() {}
    init(id: String, allow: Bool) { self.id = id; self.allow = allow }
    func perform() async throws -> some IntentResult {
        if let p = Store.pairing { _ = await Relay.answer(p, id: id, allow: allow) }
        return .result()
    }
}
#endif
