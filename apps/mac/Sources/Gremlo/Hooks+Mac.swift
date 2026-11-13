import GremloCore
import AppKit
import CryptoKit
import Network
import UserNotifications

// Reminders, the pet's click view and the local hook server (moved out of main.swift unchanged).

// Nudges you back when Claude Code is done or waiting on you. Cosmetic: never touches hooks' replies, balances or spending.
final class Reminders {
    let pet: Pet
    var message: String?
    var project: String?
    var timer: Timer?

    init(pet: Pet) { self.pet = pet }

    func handle(_ hook: [String: Any]) {
        switch hook["hook_event_name"] as? String {
        case "Stop": arm("Claude Code is done", hook)
        case "PermissionRequest": arm(approval, hook)
        case "Notification" where hook["notification_type"] as? String == "permission_prompt": arm(approval, hook)
        case "UserPromptSubmit", "SessionEnd": cancel()
        // The approval was answered and tools are running again.
        case "PreToolUse", "PostToolUse": if message == approval { cancel() }
        default: break
        }
    }

    let approval = "Claude Code needs your approval"

    func arm(_ text: String, _ hook: [String: Any]) {
        message = text
        project = (hook["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        reschedule()
    }

    func cancel() {
        message = nil
        timer?.invalidate()
        timer = nil
    }

    // Also called when the interval setting changes.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard message != nil, reminderMinutes > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: reminderMinutes * 60, repeats: true) { [weak self] _ in self?.fire() }
    }

    func fire() {
        guard let message else { return }
        notify(title: message, body: project.map { "In \($0)" } ?? "Back to your terminal")
        pet.wave()
    }

    // UNUserNotificationCenter throws without a bundle id (swift run has none); osascript works either way.
    func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return osascript(title, body) }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return DispatchQueue.main.async { self.osascript(title, body) } }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "gremlo-reminder", content: content, trigger: nil))
        }
    }

    func osascript(_ title: String, _ body: String) {
        func quote(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ") + "\""
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \(quote(body)) with title \(quote(title))"]
        do { try p.run() } catch { print("reminder not shown: \(error)") }
    }
}

// Takes clicks on the pet only while the panel isn't click-through (see Pet.updateCursor).
final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Minimal HTTP listener for the hooks. Replies 200 with an empty body at once, never a decision.
final class HookServer {
    let listener: NWListener
    let onEvent: ([String: Any]) -> Void
    /// PermissionRequest: the connection stays open until `reply` is called with the user's answer (or nil).
    var onPermission: (([String: Any], @escaping (Data?) -> Void) -> Void)?
    /// Git hooks (R4 §4) post one line: {"type":"git","event":...,"repo":<hash>}.
    var onGit: ((GitEvent) -> Void)?

    init(port: UInt16, onEvent: @escaping ([String: Any]) -> Void) throws {
        self.onEvent = onEvent
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.read(conn, Data())
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                if case .posix(.EADDRINUSE) = err {
                    print("Port 47474 is taken: \(productName) is probably already running. Stop it with: pkill -x Gremlo")
                } else {
                    print("hook server failed: \(err)")
                }
                exit(1)
            }
        }
        listener.start(queue: .main)
    }

    func read(_ conn: NWConnection, _ buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self).lowercased()
                let length = head.split(separator: "\r\n")
                    .first { $0.hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
                    .map { max(0, $0) } ?? 0 // a negative length would trap in prefix()
                let body = buf[end.upperBound...]
                if body.count >= length || done || err != nil {
                    let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                    self.finish(conn, path: path, body: Data(body.prefix(length)))
                    return
                }
            }
            if done || err != nil || buf.count > 8_000_000 { conn.cancel(); return }
            self.read(conn, buf)
        }
    }

    func respond(_ conn: NWConnection, _ body: Data?) {
        let b = body ?? Data()
        var reply = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(b.count)\r\nConnection: close\r\n\r\n".utf8)
        reply.append(b)
        conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() })
    }

    func finish(_ conn: NWConnection, path: String, body: Data) {
        if path == "/git" {
            respond(conn, nil)
            if let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let e = GitEvent.parse(j) { onGit?(e) }
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], json["hook_event_name"] is String else {
            respond(conn, nil); return
        }
        if path == "/claude/permission", let onPermission {
            // held open until the user answers on a surface; the answer is the hook's output
            var replied = false
            onPermission(json) { [weak self] data in
                guard !replied else { return }
                replied = true
                self?.respond(conn, data)
            }
        } else {
            respond(conn, nil)  // every other event: answer at once, no decision
        }
        onEvent(json)
    }
}
