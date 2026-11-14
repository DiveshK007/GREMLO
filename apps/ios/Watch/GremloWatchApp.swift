import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

@main
struct GremloWatchApp: App {
    @StateObject var model = WatchModel()
    var body: some Scene { WindowGroup { WatchView().environmentObject(model) } }
}

/// The pairing comes from the phone; the Watch reads the relay itself. Haptics: a knock when something new is
/// waiting, success when a run ends; silent while the Mac is quiet (screen share, meeting).
@MainActor final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var state = Store.state
    @Published var note = ""
    private var seen: Set<String> = []
    private var lastDone: Date?

    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { await self?.poll() } }
    }

    func poll() async {
        guard let p = Store.pairing, let s = await Relay.fetch(p) else { return }
        let fresh = s.waiting.filter { !seen.contains($0.id) }
        if !fresh.isEmpty && !s.quiet {
            // notch feel #23: the strong buzz is the Watch's, a notification then a click 0.4 s later
            WKInterfaceDevice.current().play(.notification)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WKInterfaceDevice.current().play(.click) }
        }
        if let d = s.doneAt, d != lastDone, lastDone != nil, !s.quiet { WKInterfaceDevice.current().play(.success) }
        lastDone = s.doneAt
        seen.formUnion(s.waiting.map(\.id))
        state = s
        Store.state = s
        WidgetCenter.shared.reloadAllTimelines()
    }

    func answer(_ a: PhoneApproval, allow: Bool) async {
        guard let p = Store.pairing, !a.risky else { return }
        note = await Relay.answer(p, id: a.id, allow: allow) ? (allow ? "Allowed once" : "Denied") : "No connection"
    }

    nonisolated func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) {
        let ctx = s.receivedApplicationContext
        Task { @MainActor in self.take(ctx) }
    }
    nonisolated func session(_ s: WCSession, didReceiveApplicationContext ctx: [String: Any]) { Task { @MainActor in self.take(ctx) } }
    private func take(_ ctx: [String: Any]) {
        guard let code = ctx["pairing"] as? String else { return }
        Store.pairing = PhonePairing.from(code: code)
        if Store.pairing == nil { Store.state = nil; state = nil }
        Task { await poll() }
    }
}

struct WatchView: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        NavigationStack {
            if let s = model.state {
                List {
                    HStack {
                        ZStack {
                            Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                            Circle().trim(from: 0, to: PhoneRules.ring(startedAt: s.running ? s.startedAt : nil, now: Date())).stroke(.orange, lineWidth: 4).rotationEffect(.degrees(-90))
                            PetFace(species: s.species, row: 14).padding(6)
                        }.frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text(s.name).font(.headline)
                            Text(isStale(s) ? "Mac not reachable" : s.running ? "\(s.tools) tools" : s.mood).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if !s.waiting.isEmpty {
                        NavigationLink("\(s.waiting.count) waiting on you") { WaitingList() }.foregroundStyle(.orange)
                    }
                    if !model.note.isEmpty { Text(model.note).font(.caption2) }
                }
            } else {
                Text("Pair Gremlo on your iPhone").font(.footnote).multilineTextAlignment(.center)
            }
        }
    }
}

struct WaitingList: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        List(model.state?.waiting ?? []) { a in
            VStack(alignment: .leading, spacing: 6) {
                Text(a.tool).font(.headline)
                Text(a.summary).font(.caption2.monospaced()).lineLimit(3)
                if a.risky {
                    Text("Open on the Mac").font(.caption2.bold()).foregroundStyle(.orange)
                } else {
                    HStack {
                        Button("Deny") { Task { await model.answer(a, allow: false) } }.tint(.red)
                        Button("Allow") { Task { await model.answer(a, allow: true) } }.tint(.green)
                    }
                }
            }
        }
    }
}
