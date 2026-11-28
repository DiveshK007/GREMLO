import AppKit
import GremloCore

// "Send diagnostics" (Settings, Privacy), off by default. While on, failures are counted on this Mac, and at most
// once a day the counts and any new Gremlo crash reports go to POST /diagnostics, unsigned so they can't be tied to
// the pet or this Mac. The exact report is built and tested in GremloCore/Diagnostics.swift.
final class DiagnosticsController {
    unowned let backend: Backend
    static var on: Bool { defaults.bool(forKey: "diagnostics") }

    init(backend: Backend) {
        self.backend = backend
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.sendIfDue() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.sendIfDue() }
    }

    /// Counts one failure, only while diagnostics are on.
    func count(_ c: Diagnostics.Count) {
        guard Self.on else { return }
        var d = defaults.dictionary(forKey: "diag.counts") as? [String: Int] ?? [:]
        d[c.rawValue, default: 0] += 1
        defaults.set(d, forKey: "diag.counts")
    }

    func set(_ on: Bool) {
        defaults.set(on, forKey: "diagnostics")
        // a fresh start: nothing counted while it was off, and no old crash is sent as new
        defaults.removeObject(forKey: "diag.counts")
        defaults.set(Date(), forKey: "diag.since")
    }

    /// The report as it would go out now, exactly.
    func report() -> [String: Any] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var sys = utsname(); uname(&sys)
        let arch = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Diagnostics.report(version: Updates.shared.version, os: "\(os.majorVersion).\(os.minorVersion)", arch: arch,
                                  counts: defaults.dictionary(forKey: "diag.counts") as? [String: Int] ?? [:], crashes: newCrashes())
    }

    /// Gremlo's own crash reports written since the last send (or since diagnostics were turned on).
    private func newCrashes() -> [Diagnostics.Crash] {
        let since = defaults.object(forKey: "diag.since") as? Date ?? Date()
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("Gremlo") && $0.pathExtension == "ips" }
            .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) > since }
            .compactMap { (try? String(contentsOf: $0, encoding: .utf8)).flatMap(Diagnostics.crash(ips:)) }
    }

    private func sendIfDue() {
        guard Self.on else { return }
        if let last = defaults.object(forKey: "diag.sent") as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        let r = report()
        guard !((r["counts"] as? [String: Int]) ?? [:]).isEmpty || !((r["crashes"] as? [Any]) ?? []).isEmpty else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]), let url = URL(string: backend.base + "/diagnostics") else { return }
        // not Backend.request: that signs with this Mac's key, and a report must not be tied to the pet or the Mac
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }  // kept for the next try
            DispatchQueue.main.async {
                defaults.removeObject(forKey: "diag.counts")
                defaults.set(Date(), forKey: "diag.sent")
                defaults.set(Date(), forKey: "diag.since")
                defaults.set(String(decoding: body, as: UTF8.self), forKey: "diag.last")
            }
        }.resume()
    }
}

extension Backend {
    func diagnosticsGroup() -> NSView {
        let w = pageWidth
        let what = "Off by default. When on, at most once a day: the app version, the macOS version, the chip (Apple silicon or Intel), how many times each of these happened: "
            + Diagnostics.Count.allCases.map(\.plain).joined(separator: ", ")
            + "; and for a crash, its type and the function names on the thread that crashed. Never your pet's name, your account, this Mac's key, file paths, prompts, commands or anything your agent did. Sent without a signature, so it can't be tied to you; the server sees your address to limit how often it's sent and doesn't keep it."
        return UI.group("Diagnostics", [
            UI.row("Send diagnostics", what, Toggle(on: DiagnosticsController.on, target: self, action: #selector(toggleDiagnostics(_:)), label: "Send diagnostics"), width: w),
            UI.row("What's sent", "The exact report, as it would go out now.", Btn("Show", target: self, action: #selector(showDiagnostics)), width: w),
        ], width: w)
    }
    @objc func toggleDiagnostics(_ b: NSButton) { diagnostics.set(b.state == .on); settings.reload() }
    @objc func showDiagnostics() {
        let now = (try? JSONSerialization.data(withJSONObject: diagnostics.report(), options: [.prettyPrinted, .sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let a = NSAlert()
        a.messageText = DiagnosticsController.on ? "The next diagnostics report" : "Diagnostics are off: nothing is sent"
        a.informativeText = now + (defaults.string(forKey: "diag.last").map { "\n\nLast sent:\n\($0)" } ?? "")
        a.runModal()
    }
}
