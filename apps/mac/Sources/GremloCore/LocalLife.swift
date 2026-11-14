// A pet the server can't vouch for (not registered yet, server or network down) still lives on this Mac: it walks,
// reacts to hooks and holds approvals. Only paid thinking and sponsored lines stop. Its mood is "local", which is not
// a money tier, so nothing pretends to know the budget; the menu panel says why.
public enum LocalLife {
    public static let mood = "local"
    public enum Why: Equatable, Sendable { case unregistered, serverDown, offline }

    /// From the pet request's failure: "HTTP 404" means the server answered and doesn't know this pet.
    public static func why(error: String) -> Why { error.hasPrefix("HTTP 404") ? .unregistered : .serverDown }

    /// The bubble, shown once per cause.
    public static func bubble(_ w: Why, pet: String) -> String {
        switch w {
        case .unregistered: return "\(pet) isn't registered yet"
        case .serverDown: return "Can't reach the server"
        case .offline: return "Offline"
        }
    }

    /// The menu panel's line, for as long as the cause lasts.
    public static func panel(_ w: Why, pet: String) -> String {
        switch w {
        case .unregistered: return "\(pet) isn't registered yet: get your pet on the web app. Until then no lines and no paid thinking."
        case .serverDown: return "Can't reach the server: no lines and no paid thinking for now."
        case .offline: return "Offline: no lines and no paid thinking until the network is back."
        }
    }
}
