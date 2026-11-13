import GremloCore
import AppKit
import CryptoKit
import Network
import UserNotifications

// ---- Device key (PLAN_V2 A3) ----
// A P-256 key inside this Mac's Secure Enclave. The blob in UserDefaults is opaque and only usable by this chip;
// the private key never leaves it. Views, think calls and clicks are signed with it once the pet is paired.
Migrate.run()  // before anything reads settings or the device key
let deviceSigner: SecureEnclave.P256.Signing.PrivateKey? = {
    guard SecureEnclave.isAvailable else { return nil }
    let store = "deviceKey"
    if let blob = UserDefaults.standard.data(forKey: store), let k = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) { return k }
    guard let k = try? SecureEnclave.P256.Signing.PrivateKey() else { return nil }
    UserDefaults.standard.set(k.dataRepresentation, forKey: store)
    return k
}()

func b64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
let devicePublicKey: String? = deviceSigner.map { b64url($0.publicKey.x963Representation) }

/** Signature over the server's canonical string: METHOD, path, unix ms, SHA-256 hex of the body. */
func deviceSign(method: String, path: String, body: Data) -> (key: String, time: String, sig: String)? {
    guard let k = deviceSigner, let pub = devicePublicKey else { return nil }
    let time = String(Int64(Date().timeIntervalSince1970 * 1000))
    let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
    let message = "\(method)\n\(path)\n\(time)\n\(hash)"
    guard let sig = try? k.signature(for: Data(message.utf8)) else { return nil }
    return (pub, time, b64url(sig.derRepresentation))
}

let tickHz = 30.0
// Seconds of quiet after the agent stops before the pet climbs home. Override with GREMLO_HOME_AFTER.
// Popover settings, persisted in UserDefaults. GREMLO_HOME_AFTER still overrides at launch.
let defaults = UserDefaults.standard
var homeAfter = TimeInterval(Legacy.env("HOME_AFTER") ?? "") ?? (defaults.object(forKey: "homeAfter") as? Double ?? 75)
var walkSpeed = defaults.object(forKey: "walkSpeed") as? Double ?? 1
// Sponsored hooks are opt-in: off until the developer turns them on (asked once on first launch).
var sponsoredOn = defaults.object(forKey: "sponsored") as? Bool ?? false
var quietHours = defaults.object(forKey: "quietHours") as? Bool ?? false // opt-in: developers code at night; when on, no hooks 22:00-08:00
let dailyViewCap = 120 // the server enforces the same cap
func inQuietHours(_ d: Date = Date()) -> Bool {
    let h = Calendar.current.component(.hour, from: d)
    return quietHours && (h >= 22 || h < 8)
}
// Off: on every normal desktop, never over full-screen apps. On: over full-screen apps too.
// (Pinning to the launch Space hid the pet on the desktop whenever Gremlo was started from a full-screen app.)
var allDesktops = defaults.bool(forKey: "allDesktops")
// Come-back reminders every N minutes after Stop or an approval request; 0 is off.
var reminderMinutes = defaults.object(forKey: "reminderMinutes") as? Double ?? 5
func spacesBehavior() -> NSWindow.CollectionBehavior {
    allDesktops ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary] : [.canJoinAllSpaces, .stationary]
}

enum PetState: String, CaseIterable {
    case greet, walk, idle, sign, flag, celebrate, fail, climb, eat, hover, annoy, backflip, moonwalk
    case sit, yawn, gaze, grabbed, thrown, land, edgepeek, night, tools, special, hatch, evolve
    case chase, gulp, covereyes, tangled, juggle, wrist, focus
    /// The pack row this state draws. Holding the line is the hold row, with the plate overhead.
    var row: Row { self == .sign ? .hold : Row(rawValue: rawValue)! }
}

let loopingStates: Set<PetState> = [.walk, .climb, .idle, .sign, .flag, .hover, .annoy, .moonwalk, .sit, .gaze, .grabbed, .thrown, .night, .tools, .hatch, .tangled, .focus, .chase]

// Where the pet is, separate from what it is doing.
enum Path: String { case home, falling, floor, toWall, climbing, ceiling, entering, held, airborne }

// A species pack (GremloCore) prepared for drawing. See assets/pets/<id>/pet.json and docs/design/1.0.
struct Strip {
    let row: Row              // the row actually drawn (after fallbacks)
    let frames: [CGImage]     // that row's frames
    let subset: [Int]?        // fallback frames within the row, or nil for the spec's sequence
    let rotated: Bool         // walk standing in for climb, rotated onto the wall
}

struct Skin {
    let name: String          // species id, the pack folder
    let loaded: LoadedPack
    let species: Species?
    let accent: CGColor
    let size: CGSize
    let footPadding: CGFloat
    let strips: [PetState: Strip]
    let doors: [DoorState: CGImage]  // packs carry no door art yet; the default door is drawn
    let scale: CGFloat               // points per sheet pixel
    var pack: Pack { loaded.pack }
    var geometry: PetGeometry { PetGeometry(cellW: pack.cell.w, cellH: pack.cell.h, scale: scale) }
}

// The packaged .app carries assets in Contents/Resources/assets; swift run reads the repo's top-level assets/.
let assetsDir: URL = {
    if let r = Bundle.main.resourceURL?.appendingPathComponent("assets/pets"), FileManager.default.fileExists(atPath: r.path) { return r.deletingLastPathComponent() }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("assets")
}()

func hexColor(_ hex: String) -> CGColor {
    guard let c = RGB(hex: hex) else { return CGColor(red: 1, green: 0x5A / 255.0, blue: 0x3C / 255.0, alpha: 1) }
    return CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
}

// Loads `want` (or GREMLO_SKIN, or the saved species, or Gremlo); falls back to the first species that loads.
func loadSkin(_ want: String? = nil) -> Skin? {
    let pick = want ?? Legacy.env("SKIN") ?? defaults.string(forKey: "skin") ?? Roster.defaultId
    let order = [pick] + Roster.all.map(\.id).filter { $0 != pick }
    for id in order { if let s = loadSkin(id: id) { return s } }
    print("no loadable pet in \(assetsDir.path)/pets")
    return nil
}

func loadSkin(id: String, dir: URL? = nil) -> Skin? {
    let loaded: LoadedPack
    do { loaded = try LoadedPack.load(dir: dir ?? assetsDir.appendingPathComponent("pets/\(id)")) } catch {
        print("pet \(id): \(error.localizedDescription)")
        return nil
    }
    var strips: [PetState: Strip] = [:]
    for s in PetState.allCases {
        guard let r = Fallback.resolve(s.row, in: loaded.pack), let frames = loaded.frames[r.row] else { continue }
        strips[s] = Strip(row: r.row, frames: frames, subset: r.frames, rotated: r.rotated)
    }
    guard strips[.walk] != nil else { print("pet \(id) has no walk frames"); return nil }
    let scale: CGFloat = 2.0 / 7  // one sprite unit (7 sheet px) draws at 2 points
    let (cw, ch) = loaded.pack.cell
    print("pet \(id): pack v\(loaded.pack.version), \(loaded.frames.count) rows\(loaded.pack.canHoldLine ? "" : ", can't hold the line")")
    return Skin(name: id, loaded: loaded, species: Roster.species(id), accent: hexColor(loaded.pack.gremlo.accent),
                size: CGSize(width: CGFloat(cw) * scale, height: CGFloat(ch) * scale),
                footPadding: CGFloat(ch - 194) * scale, strips: strips, doors: [:], scale: scale)
}

// Design tokens: Ink, Paper. The accent comes from the active pet.
let inkColor = CGColor(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0B / 255.0, alpha: 1)
let paperColor = CGColor(red: 0xF4 / 255.0, green: 0xF2 / 255.0, blue: 0xED / 255.0, alpha: 1)

// The screen with the menu bar (and the notch, if there is one).
var mainScreen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

func overlayPanel(_ size: CGSize, level: NSWindow.Level) -> NSPanel {
    let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = level
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = spacesBehavior()
    let view = NSView(frame: NSRect(origin: .zero, size: size))
    view.wantsLayer = true
    panel.contentView = view
    return panel
}

assert(nearGain("1000000000000000000000000", "1000200000000000000000000") == "+0.0002")
assert(nearGain("123456789012345678901234567", "123456789012345678901234568") == "+0.000000000000000000000001")
assert(near4("19279999998320000000000") == "0.0192" && near4("0") == "0.0000" && near4("1000000000000000000000000000") == "1000.0000")
assert(near4("99999999999999999999") == "0.0000" && near4(nil) == "\u{2014}")
assert(near4("-5") == "\u{2014}" && near4("0x1f") == "\u{2014}" && near4(" 5") == "\u{2014}" && near4("") == "\u{2014}")
assert(!staysHome(mood: "hungry", agentWorking: true) && !staysHome(mood: "hungry", agentWorking: false), "a hungry pet still shows the sign")
assert(!staysHome(mood: "asleep", agentWorking: true) && staysHome(mood: "asleep", agentWorking: false), "only an idle, asleep pet stays home")
assert(!staysHome(mood: "thriving", agentWorking: true) && !staysHome(mood: "stable", agentWorking: false))
assert(nearGain("5", "5") == nil && nearGain("5", "4") == nil && nearGain(nil, "5") == nil)
do { // WaitClock: prompt to stop counts, a lost stop is capped, a new prompt closes the open stretch
    var w = WaitClock(); let t0 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())! // away from midnight
    w.handle("UserPromptSubmit", at: t0); w.handle("PreToolUse", at: t0 + 60); w.handle("Stop", at: t0 + 120)
    assert(w.minutes(at: t0 + 130) == 2)
    w.handle("UserPromptSubmit", at: t0 + 200); w.handle("UserPromptSubmit", at: t0 + 200 + 7200)
    assert(w.minutes(at: t0 + 200 + 7200) == 62)
}
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
applyTheme()
guard let skin = loadSkin() else { exit(1) }
let door = Door(art: skin.doors, scale: skin.scale, accent: skin.accent)
let pet = Pet(skin: skin, door: door)
let backend = Backend(pet: pet)
let server: HookServer
do {
    server = try HookServer(port: 47474) { hook in
        backend.run.event(hook, approvalsAnswered: backend.broker.approvalsAnswered)
        backend.growth.hook(hook)
        backend.hunt.hook(hook)
        backend.live.hooked(hook["hook_event_name"] as? String ?? "")
        if backend.companions.route(hook) { backend.render(); return }  // another agent's companion took it
        backend.broker.sawEvent(session: hook["session_id"] as? String ?? "", tool: hook["tool_name"] as? String, event: hook["hook_event_name"] as? String ?? "")
        // the command text never leaves the Mac: it only picks the prop (and, later, spots test runs)
        pet.handle(event: hook["hook_event_name"] as! String, notification: hook["notification_type"] as? String,
                   tool: hook["tool_name"] as? String, command: (hook["tool_input"] as? [String: Any])?["command"] as? String)
        backend.waited.handle(hook["hook_event_name"] as! String)
        backend.think(hook)
        backend.reminders.handle(hook)
        backend.render()
    }
    server.onPermission = { payload, reply in backend.broker.receive(payload, reply: reply) }
    server.onGit = { e in backend.hunt.git(e) }
} catch {
    print("cannot listen on 47474: \(error)")
    exit(1)
}
_ = backend.live  // the notch panel
_ = backend.privacy  // detectors, hot keys, stream mode
_ = backend.commandSocket  // the gremlo CLI, Shortcuts and Raycast
_ = backend.social  // team relay, park, guestbook visits
_ = backend.phone  // the paired phone and Watch
_ = backend.github  // opt-in: merged PRs and review visits through gh
NSAppleEventManager.shared().setEventHandler(backend, andSelector: #selector(Backend.handleURL(_:withReplyEvent:)),
                                             forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
print("\(productName) running, hooks on 127.0.0.1:47474, home after \(Int(homeAfter))s")
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { backend.askSponsoredOnce() }
ClaudeHooks.refreshScriptIfStale()
app.run()
