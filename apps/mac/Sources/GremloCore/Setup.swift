// The first-run setup's steps and its plain reasons for each failure. Pure, so every message is tested.

public enum Setup {
    public enum Step: Int, CaseIterable, Sendable { case welcome, pet, pair, claude, test, done }

    /// The session id the setup's test event carries, so the app knows it isn't a real agent run.
    public static let testSession = "gremlo-setup-test"

    /// Why looking the pet up failed, from the request's failure text ("HTTP 404 {...}" or a network error); nil when it worked.
    public static func petProblem(name: String, error: String?) -> String? {
        guard let error else { return nil }
        if error.hasPrefix("HTTP 404") { return "No pet called \(name) yet. Get one on the web (it takes a minute), then press Retry." }
        if error.hasPrefix("HTTP ") { return "The server said: \(ServerError.text(error)). Press Retry." }
        return "Can't reach the server: \(error). Check your connection, then press Retry."
    }

    /// Why the pairing step isn't done yet. `paired` is the server's answer for this Mac's key; nil means no answer.
    public static func pairProblem(secureEnclave: Bool, paired: Bool?, error: String?) -> String? {
        if !secureEnclave { return "This Mac has no Secure Enclave, so its views can't be signed or paid. The pet still works." }
        if let error { return "Can't check the pairing: \(ServerError.text(error)). Press Retry." }
        if paired == true { return nil }
        return "Not paired yet. Sign the message in the browser with the wallet that owns the pet, then press Retry."
    }

    /// Why the test event didn't reach the app, checked in the order the hook needs things.
    public static func testProblem(connected: Bool, scriptExists: Bool, headerExists: Bool, heard: Bool, exitCode: Int32?) -> String? {
        if heard { return nil }
        if !connected { return "Claude Code isn't connected yet. Go back a step and press Connect." }
        if !scriptExists { return "The hook script is missing from ~/.gremlo. Go back a step and press Connect again." }
        if !headerExists { return "The hook's key file ~/.gremlo/hook-header is missing. Quit and reopen Gremlo, then press Retry." }
        if let exitCode, exitCode != 0 { return "The hook script failed (exit \(exitCode)). Check that bash and curl work in Terminal, then press Retry." }
        return "The test didn't reach the app. Another app may be using port 47474 (check with lsof -i :47474). Press Retry."
    }
}
