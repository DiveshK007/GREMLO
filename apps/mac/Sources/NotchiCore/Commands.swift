import Foundation

// R2 §10: the `notchi` CLI, the notchi:// URL scheme, Shortcuts and Raycast all send the same requests to the app
// over its local socket. No request can spend, pay, change the payout address or allow a risky command.

public struct Request: Codable, Equatable, Sendable {
    public var cmd: String
    public var args: [String: String]
    public init(_ cmd: String, _ args: [String: String] = [:]) { self.cmd = cmd; self.args = args }
}

public struct Reply: Codable, Equatable, Sendable {
    public var ok: Bool
    public var text: String
    public var data: [String: String]?
    public init(ok: Bool, text: String, data: [String: String]? = nil) { self.ok = ok; self.text = text; self.data = data }
}

public enum CommandError: Error, Equatable, CustomStringConvertible {
    case usage(String)
    public var description: String { if case let .usage(s) = self { return s }; return "" }
}

public enum Commands {
    public static let socketPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Notchi/notchi.sock").path
    public static let sayMax = 80, sayEvery = 10.0

    /// Commands the app answers. Nothing here moves money, touches the payout address or allows a risky command.
    public static let known: Set<String> = ["status", "say", "pause", "resume", "focus", "pet", "celebrate", "hook", "log", "trick", "approve", "preview"]

    public static let usage = """
    usage: notchi <command>
      status [--json]                 pet, earner state, agents
      say "<text>"                    a bubble tagged "you" (80 chars, once every 10 s)
      pause [dur] | resume            pets home, lines off, counters frozen (default 30m)
      focus <dur>                     25m, 50m or 90m
      pet <species> [--agent <id>]    species for the earner, or for one agent's companion
      celebrate                       plays celebrate once
      trick <backflip|juggle|moonwalk>  a learned trick
      approve next [deny]             answers the oldest ordinary approval (never a risky one)
      hook install|remove <claude|git> [--global]
      log [--today] [--json]          the day's events
      validate <dir> | new <name> | preview <dir> | submit <dir> --creator <name>   creator tools
      verify <campaign> [--server URL]   replays a campaign's public log against its bill
    """

    /// "30", "30m", "1h", "90s" (rounded up to a minute), "1h30m".
    public static func minutes(_ s: String) -> Int? {
        if let n = Int(s), n > 0 { return n }
        var total = 0.0, num = ""
        for c in s.lowercased() {
            if c.isNumber { num.append(c); continue }
            guard let v = Double(num) else { return nil }
            switch c { case "h": total += v * 60; case "m": total += v; case "s": total += v / 60; default: return nil }
            num = ""
        }
        guard num.isEmpty, total > 0 else { return nil }
        return Int(total.rounded(.up))
    }

    /// argv without the program name. `cwd` rides along for commands that act on the current repo.
    public static func parse(_ argv: [String], cwd: String) throws -> Request {
        guard let cmd = argv.first else { throw CommandError.usage(usage) }
        let rest = Array(argv.dropFirst())
        let flags = Set(rest.filter { $0.hasPrefix("--") })
        let words = rest.filter { !$0.hasPrefix("--") }
        func flagValue(_ f: String) -> String? { rest.firstIndex(of: f).flatMap { rest.indices.contains($0 + 1) ? rest[$0 + 1] : nil } }
        switch cmd {
        case "status": return Request("status", flags.contains("--json") ? ["json": "1"] : [:])
        case "say":
            let text = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw CommandError.usage("say needs text") }
            guard text.count <= sayMax else { throw CommandError.usage("say: up to \(sayMax) characters") }
            return Request("say", ["text": text])
        case "pause":
            let m = words.first.map { minutes($0) } ?? 30
            guard let m, m <= 24 * 60 else { throw CommandError.usage("pause [dur], e.g. 30m or 2h") }
            return Request("pause", ["min": "\(m)"])
        case "resume", "celebrate": return Request(cmd)
        case "focus":
            guard let w = words.first, let m = minutes(w), [25, 50, 90].contains(m) else { throw CommandError.usage("focus 25m, 50m or 90m") }
            return Request("focus", ["min": "\(m)"])
        case "pet":
            guard let s = words.first else { throw CommandError.usage("pet <species> [--agent <id>]") }
            let id = s.hasPrefix("notchi") ? s : "notchi-\(s)"
            var a = ["species": s == "notchi" ? "notchi" : id]
            if let agent = flagValue("--agent") { a["agent"] = agent }
            return Request("pet", a)
        case "trick":
            guard let t = words.first, Trick(rawValue: t) != nil else { throw CommandError.usage("trick backflip|juggle|moonwalk") }
            return Request("trick", ["name": t])
        case "approve":
            guard words.first == "next" else { throw CommandError.usage("approve next [deny]") }
            return Request("approve", ["answer": words.dropFirst().first == "deny" ? "deny" : "allow"])
        case "hook":
            guard words.count >= 2, ["install", "remove"].contains(words[0]), ["claude", "git"].contains(words[1]) else {
                throw CommandError.usage("hook install|remove claude|git [--global]")
            }
            var a = ["action": words[0], "agent": words[1], "cwd": cwd]
            if flags.contains("--global") { a["global"] = "1" }
            return Request("hook", a)
        case "log":
            var a: [String: String] = [:]
            if flags.contains("--json") { a["json"] = "1" }
            if flags.contains("--today") { a["today"] = "1" }
            return Request("log", a)
        case "preview":
            guard let d = words.first else { throw CommandError.usage("preview <dir>") }
            return Request("preview", ["dir": URL(fileURLWithPath: d, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)).standardized.path])
        default: throw CommandError.usage(usage)
        }
    }

    /// notchi://say?text=…, notchi://pause?min=30, notchi://focus?min=25 (and resume, celebrate, status).
    public static func fromURL(_ url: URL) -> Request? {
        guard url.scheme == "notchi", let host = url.host else { return nil }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch host {
        case "say": return v("text").flatMap { try? parse(["say", $0], cwd: "/") }
        case "pause": return try? parse(["pause"] + (v("min").map { [$0] } ?? []), cwd: "/")
        case "focus": return v("min").flatMap { try? parse(["focus", $0], cwd: "/") }
        case "resume", "celebrate", "status": return Request(host)
        default: return nil  // nothing over a URL can approve, install hooks or change the pet
        }
    }
}

/// `say` at most once every 10 s, never during a screen share.
public struct SayLimiter: Sendable {
    var last: Date?
    public init() {}
    public mutating func allow(now: Date, screenShared: Bool) -> Bool {
        guard !screenShared, last.map({ now.timeIntervalSince($0) >= Commands.sayEvery }) ?? true else { return false }
        last = now
        return true
    }
}

// MARK: - Creator tools: validating a species pack (R2 §13)

public enum PackCheck {
    /// Problems with a pack folder, or an empty list when it loads and matches the spec.
    public static func problems(_ dir: URL) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        let json = dir.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: json) else { return ["pet.json is missing"] }
        let pack: Pack
        do { pack = try Pack.decode(data) } catch { return ["pet.json doesn't parse: \(error)"] }
        let sheet = ["spritesheet.webp", "spritesheet.png"].map { dir.appendingPathComponent($0) }.first { fm.fileExists(atPath: $0.path) }
        if sheet == nil { out.append("spritesheet.webp or spritesheet.png is missing") }
        if let s = sheet, let img = Images.load(s) {
            let m = pack.notchi, rows = m.rows.count, cw = m.cell.first ?? 192, ch = m.cell.last ?? 208
            if img.width != m.columns * cw || img.height != rows * ch {
                out.append("spritesheet is \(img.width)x\(img.height); \(rows) rows of \(m.columns) \(cw)x\(ch) cells need \(m.columns * cw)x\(rows * ch)")
            }
        } else if sheet != nil { out.append("spritesheet can't be read") }
        if pack.notchi.accessories != nil && !fm.fileExists(atPath: dir.appendingPathComponent("accessories.png").path) { out.append("accessories.png is declared but missing") }
        if pack.notchi.signKit != nil && !fm.fileExists(atPath: dir.appendingPathComponent("signkit.png").path) { out.append("signkit.png is declared but missing") }
        if out.isEmpty, (try? LoadedPack.load(dir: dir)) == nil { out.append("the pack doesn't load") }
        return out
    }
}

// MARK: - The local socket

/// A Unix socket only this user can open (0600). One JSON request line in, one JSON reply line out.
public final class CommandSocket {
    public let path: String
    var fd: Int32 = -1
    let handle: (Request) -> Reply
    let onMain: Bool

    /// `onMain`: run the handler on the main thread (the app); tests answer on the socket's own queue.
    public init(path: String = Commands.socketPath, onMain: Bool = true, handle: @escaping (Request) -> Reply) {
        self.path = path
        self.onMain = onMain
        self.handle = handle
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: addr.sun_path) - 1))
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = b } }
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0, listen(fd, 8) == 0 else { close(fd); fd = -1; return }
        chmod(path, 0o600)
        let listenFd = fd
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let c = accept(listenFd, nil, nil)
                guard c >= 0 else { if errno == EINTR { continue } else { return } }
                self?.serve(c)
            }
        }
    }

    public var listening: Bool { fd >= 0 }

    private func serve(_ c: Int32) {
        var buf = [UInt8](repeating: 0, count: 65536), data = Data()
        while !data.contains(10) && data.count < 65536 {
            let n = read(c, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        let line = data.split(separator: 10).first.map { Data($0) } ?? Data()
        var reply = Reply(ok: false, text: "bad request")
        if let req = try? JSONDecoder().decode(Request.self, from: line) {
            reply = onMain ? DispatchQueue.main.sync { handle(req) } : handle(req)
        }
        var out = (try? JSONEncoder().encode(reply)) ?? Data()
        out.append(10)
        _ = out.withUnsafeBytes { write(c, $0.baseAddress, out.count) }
        close(c)
    }
}


public enum CommandClient {
    /// Sends one request and waits for the reply; nil when nothing is listening.
    public static func send(_ req: Request, path: String = Commands.socketPath) -> Reply? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: addr.sun_path) - 1))
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = b } }
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0 else { return nil }
        var out = (try? JSONEncoder().encode(req)) ?? Data()
        out.append(10)
        _ = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
        var data = Data(), buf = [UInt8](repeating: 0, count: 65536)
        while true { let n = read(fd, &buf, buf.count); if n <= 0 { break }; data.append(contentsOf: buf[0..<n]) }
        return try? JSONDecoder().decode(Reply.self, from: data)
    }
}
