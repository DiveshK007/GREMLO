import Foundation
import Security

/// Who may talk to the local hook server on 127.0.0.1:47474. Any local process or web page can reach a loopback port,
/// so a request must carry this install's secret (the hook script reads it from a 0600 file), and a request a browser
/// sent (an Origin header) or one aimed at another host name (DNS rebinding) is refused outright.
public enum HookAuth {
    /// 32 random bytes as 64 lowercase hex characters.
    public static func makeSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess { bytes = (0..<32).map { _ in UInt8.random(in: 0...255) } }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the secret in `dir` or makes one, and writes the header line the script sends (a file, so the secret never
    /// shows up in `ps`). Both files are 0600 in a 0700 directory.
    public static func loadOrCreate(in dir: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let secretFile = dir.appendingPathComponent("hook-secret")
        var secret = (try? String(contentsOf: secretFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if secret.count != 64 || secret.contains(where: { !$0.isHexDigit }) {
            secret = makeSecret()
            try Data(secret.utf8).write(to: secretFile, options: .atomic)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretFile.path)
        let header = dir.appendingPathComponent("hook-header")
        try Data("\(headerName): \(secret)".utf8).write(to: header, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: header.path)
        return secret
    }

    public static let headerName = "X-Gremlo-Secret"

    /// Header names lowercased; the value keeps what was sent, trimmed.
    public static func parseHead(_ head: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let i = line.firstIndex(of: ":") else { continue }
            out[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Constant-time, so response timing can't be used to guess the secret.
    public static func matches(_ given: String?, _ secret: String) -> Bool {
        guard let given, given.utf8.count == secret.utf8.count else { return false }
        return zip(given.utf8, secret.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// nil when the request may go on, else why it was refused. `needsSecret` is false for the git hooks, which only
    /// decorate (a celebration) and may already be installed in repos from before the secret existed.
    public static func refusal(headers: [String: String], secret: String, needsSecret: Bool, port: UInt16 = 47474) -> String? {
        if headers["origin"] != nil { return "a browser sent this" }
        if let host = headers["host"]?.lowercased(), !["127.0.0.1", "localhost", "127.0.0.1:\(port)", "localhost:\(port)"].contains(host) { return "wrong host" }
        if needsSecret && !matches(headers[headerName.lowercased()], secret) { return "missing or wrong secret" }
        return nil
    }
}

/// At most `max` events per `window` seconds; the rest are dropped. Used to cap paid AI calls a hook can start.
public final class SlidingLimit {
    private let max: Int
    private let window: TimeInterval
    private var hits: [Date] = []
    public init(max: Int, window: TimeInterval) { self.max = max; self.window = window }
    public func allow(_ now: Date = Date()) -> Bool {
        hits.removeAll { now.timeIntervalSince($0) >= window }
        guard hits.count < max else { return false }
        hits.append(now)
        return true
    }
}
