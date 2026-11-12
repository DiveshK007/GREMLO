import ActivityKit
import LocalAuthentication
import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct NotchiApp: App {
    @StateObject var model = Model()
    // the QR code is a notchi-pair: link, so the Camera app offers to open it here
    var body: some Scene { WindowGroup { ContentView().environmentObject(model).onOpenURL { model.pair($0.absoluteString) } } }
}

/// Polls the relay while the app is open, keeps the Live Activity and widgets current, and hands the pairing to the Watch.
@MainActor final class Model: NSObject, ObservableObject, WCSessionDelegate {
    @Published var pairing = Store.pairing
    @Published var state = Store.state
    @Published var note = ""
    private var timer: Timer?
    private var activity: Activity<RunAttributes>?

    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        // simulator checks: `simctl launch <device> dev.notchi.phone -pairCode <code>` pairs without a tap
        if pairing == nil, let c = UserDefaults.standard.string(forKey: "pairCode") { pair(c) }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { await self?.poll() } }
        Task { await poll() }
    }

    func pair(_ code: String) {
        guard let p = PhonePairing.from(code: code.trimmingCharacters(in: .whitespacesAndNewlines)) else { note = "That isn't a Notchi pairing code."; return }
        Store.pairing = p; pairing = p; note = ""
        sendToWatch()
        Task { await poll() }
    }

    func unpair() { Store.pairing = nil; Store.state = nil; pairing = nil; state = nil; sendToWatch(); endActivity() }

    func poll() async {
        guard let p = pairing, let s = await Relay.fetch(p) else { return }
        state = s
        Store.state = s
        WidgetCenter.shared.reloadAllTimelines()
        updateActivity(s)
    }

    /// Allow asks for Face ID (or the passcode); deny doesn't. The Mac takes it only if it's still waiting.
    func answer(_ a: PhoneApproval, allow: Bool) async {
        guard let p = pairing, !a.risky else { return }
        if allow {
            let ctx = LAContext()
            guard (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Allow \(a.tool) on your Mac")) == true else { return }
        }
        note = await Relay.answer(p, id: a.id, allow: allow) ? (allow ? "Allowed once" : "Denied") : "Couldn't reach the relay"
    }

    // MARK: Live Activity

    private func updateActivity(_ s: PhoneState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let w = s.waiting.first
        let content = RunAttributes.ContentState(mood: s.mood, tools: s.tools, waitingId: w?.id, waitingTool: w?.tool, waitingSummary: w?.summary,
                                                 waitingRisky: w?.risky ?? false, waitingCount: s.waiting.count)
        if s.running && !isStale(s), let start = s.startedAt {
            if let a = activity { Task { await a.update(ActivityContent(state: content, staleDate: Date().addingTimeInterval(120))) } }
            else { activity = try? Activity.request(attributes: RunAttributes(name: s.name, species: s.species, startedAt: start), content: ActivityContent(state: content, staleDate: nil)) }
        } else { endActivity() }
    }
    private func endActivity() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .default) }
    }

    // MARK: Watch

    private func sendToWatch() {
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(["pairing": pairing?.code ?? ""])
    }
    nonisolated func session(_ s: WCSession, activationDidCompleteWith st: WCSessionActivationState, error: Error?) { Task { @MainActor in self.sendToWatch() } }
    nonisolated func sessionDidBecomeInactive(_ s: WCSession) {}
    nonisolated func sessionDidDeactivate(_ s: WCSession) { s.activate() }
}

struct ContentView: View {
    @EnvironmentObject var model: Model
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Group {
                if model.pairing == nil { pairView } else { statusView }
            }
            .navigationTitle("Notchi")
        }
    }

    var pairView: some View {
        Form {
            Section("Pair with your Mac") {
                Text("In the Mac app: Settings, Phone and Watch, Pair a phone. Paste the code here (or scan it with the Camera app).")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("notchi-pair:…", text: $code, axis: .vertical).font(.footnote.monospaced()).textInputAutocapitalization(.never)
                Button("Pair") { model.pair(code) }
                Button("Paste") { code = UIPasteboard.general.string ?? "" }
                if !model.note.isEmpty { Text(model.note).foregroundStyle(.orange) }
            }
            Section { Text("Approvals travel sealed with a key only your Mac and this phone have. The relay can't read them.").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    var statusView: some View {
        List {
            if let s = model.state {
                Section {
                    HStack(spacing: 16) {
                        PetFace(species: s.species, row: s.waiting.isEmpty ? (s.mood == "asleep" ? 26 : 5) : 7).frame(width: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name).font(.title2.bold())
                            Text(isStale(s) ? "Mac not reachable" : s.mood).foregroundStyle(.secondary)
                            if s.running, let start = s.startedAt { Text(start, style: .timer).monospacedDigit() + Text(" · \(s.tools) tools").foregroundColor(.secondary) }
                        }
                    }
                }
                Section(s.waiting.isEmpty ? "Nothing waiting" : "\(s.waiting.count) waiting on you") {
                    ForEach(s.waiting) { a in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(a.tool).font(.headline)
                            Text(a.summary).font(.footnote.monospaced()).lineLimit(3)
                            if a.risky {
                                Label("Deletes, pushes or spends: open on the Mac", systemImage: "laptopcomputer").font(.footnote).foregroundStyle(.orange)
                            } else {
                                HStack {
                                    Button("Deny", role: .destructive) { Task { await model.answer(a, allow: false) } }.buttonStyle(.bordered)
                                    Button("Allow once") { Task { await model.answer(a, allow: true) } }.buttonStyle(.borderedProminent)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            } else {
                Text("Waiting for your Mac…").foregroundStyle(.secondary)
            }
            if !model.note.isEmpty { Text(model.note).foregroundStyle(.secondary) }
            Section { Button("Unpair", role: .destructive) { model.unpair() } }
        }
        .refreshable { await model.poll() }
    }
}
