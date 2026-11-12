import Foundation
import NotchiCore

// `notchi`: talks to the running app over its local socket (R2 §10). The creator tools that only read a folder
// (validate, new) run here without the app.

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

let argv = Array(CommandLine.arguments.dropFirst())
func flag(_ f: String) -> String? { argv.firstIndex(of: f).flatMap { argv.indices.contains($0 + 1) ? argv[$0 + 1] : nil } }
let server = flag("--server") ?? ProcessInfo.processInfo.environment["NOTCHI_SERVER"] ?? "http://localhost:8787"

/// GET (or POST with a JSON body) against the server; the body of any HTTP answer, or nil on a network error.
func fetch(_ path: String, body: Data? = nil) -> Data? {
    guard let url = URL(string: server + path) else { return nil }
    var req = URLRequest(url: url, timeoutInterval: 30)
    if let body { req.httpMethod = "POST"; req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    var out: Data?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, _, _ in out = d; done.signal() }.resume()
    done.wait()
    return out
}
let cwd = FileManager.default.currentDirectoryPath
if argv.isEmpty || ["-h", "--help", "help"].contains(argv[0]) { print(Commands.usage); exit(0) }

switch argv[0] {
case "validate":
    guard argv.count > 1 else { fail("validate <dir>") }
    let problems = PackCheck.problems(URL(fileURLWithPath: argv[1], relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)))
    if problems.isEmpty { print("ok: the pack loads and matches the spec"); exit(0) }
    problems.forEach { print("- \($0)") }
    exit(1)
case "new":
    guard argv.count > 1, argv[1].range(of: #"^[a-z0-9-]{2,24}$"#, options: .regularExpression) != nil else { fail("new <name> (a-z, 0-9, dashes)") }
    // starts from the Notchi pack: same rows, anchors and sheet layout, ready to redraw
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let roots = [exe.deletingLastPathComponent().appendingPathComponent("../Resources/assets/pets/notchi"),  // inside the .app
                 URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../assets/pets/notchi")]
    guard let template = roots.map(\.standardized).first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("pet.json").path) }) else { fail("can't find the template pack") }
    let dest = URL(fileURLWithPath: cwd).appendingPathComponent(argv[1])
    guard !FileManager.default.fileExists(atPath: dest.path) else { fail("\(argv[1]) already exists") }
    do { try FileManager.default.copyItem(at: template, to: dest) } catch { fail("\(error.localizedDescription)") }
    print("made \(argv[1])/ from the Notchi pack. Redraw spritesheet.png, then: notchi validate \(argv[1]) && notchi preview \(argv[1])")
    exit(0)
case "verify":
    guard argv.count > 1, argv[1].range(of: #"^[1-9][0-9]*$"#, options: .regularExpression) != nil else { fail("verify <campaign id> [--server URL]") }
    guard let data = fetch("/campaigns/\(argv[1])/log"), let log = try? JSONDecoder().decode(PublicLog.self, from: data) else { fail("can't read campaign \(argv[1])'s log from \(server)") }
    let r = LogVerify.run(log)
    print("campaign \(argv[1]): \(log.entries.count) signed reports, \(r.logged) sightings logged, \(r.billed) billed (settled \(log.billed.settled), pending \(log.billed.pending), held \(log.billed.held), voided \(log.billed.voided))")
    if r.ok { print("ok: every report is signed by a paired device, the chain is unbroken, and the log matches the bill"); exit(0) }
    r.problems.prefix(20).forEach { print("- \($0)") }
    exit(1)
case "submit":
    // a PR to notchi-pets works too; this uploads to the gallery's review queue
    guard argv.count > 1, let creator = flag("--creator") else { fail("submit <dir> --creator <name shown as credit> (only art you made)") }
    let dir = URL(fileURLWithPath: argv[1], relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)).standardized
    let problems = PackCheck.problems(dir)
    guard problems.isEmpty else { problems.forEach { print("- \($0)") }; fail("fix these first (notchi validate)") }
    var files: [String: String] = [:]
    for f in ["pet.json", "spritesheet.png", "signkit.png", "accessories.png"] {
        if let d = FileManager.default.contents(atPath: dir.appendingPathComponent(f).path) { files[f] = d.base64EncodedString() }
    }
    guard files["spritesheet.png"] != nil else { fail("submit needs spritesheet.png (export the webp to png)") }
    let body = try! JSONSerialization.data(withJSONObject: ["name": dir.lastPathComponent, "creator": creator, "ownArt": true, "files": files])
    guard let reply = fetch("/gallery", body: body), let o = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else { fail("upload failed") }
    if let e = o["error"] as? String { fail(e) }
    print("submitted for review: \(o["id"] ?? "")\n\(o["note"] ?? "")")
    exit(0)
default: break
}

let req: Request
do { req = try Commands.parse(argv, cwd: cwd) } catch { fail("\(error)") }

guard let reply = CommandClient.send(req) else { fail("the app isn't running (no socket at \(Commands.socketPath))") }
if req.args["json"] == "1", req.cmd == "status", let d = reply.data, let j = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) {
    print(String(decoding: j, as: UTF8.self))
} else {
    print(reply.text)
}
exit(reply.ok ? 0 : 1)
