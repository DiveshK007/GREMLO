import Foundation
import NotchiCore

// `notchi`: talks to the running app over its local socket (R2 §10). The creator tools that only read a folder
// (validate, new) run here without the app.

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

let argv = Array(CommandLine.arguments.dropFirst())
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
