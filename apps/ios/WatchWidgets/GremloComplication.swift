import SwiftUI
import WidgetKit

/// The Watch complication: the pet's face inside a ring that fills as the run goes (R4 §17).
@main
struct GremloComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ring", provider: RingProvider()) { e in
            RingView(e: e).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Gremlo").description("Your pet and its run.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct RingEntry: TimelineEntry { let date: Date; let state: PhoneState? }

struct RingProvider: TimelineProvider {
    func placeholder(in context: Context) -> RingEntry { RingEntry(date: Date(), state: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RingEntry) -> Void) { completion(RingEntry(date: Date(), state: Store.state)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RingEntry>) -> Void) {
        // the ring moves every few minutes while a run is on
        let s = Store.state, now = Date()
        let entries = (0..<6).map { RingEntry(date: now.addingTimeInterval(Double($0) * 300), state: s) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct RingView: View {
    @Environment(\.widgetFamily) var family
    let e: RingEntry
    var body: some View {
        let s = e.state
        let ring = PhoneRules.ring(startedAt: s?.running == true ? s?.startedAt : nil, now: e.date)
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text(s?.name ?? "Gremlo").font(.headline)
                Text(s.map { $0.waiting.isEmpty ? ($0.running ? "\($0.tools) tools" : $0.mood) : "\($0.waiting.count) waiting on you" } ?? "not paired")
                    .font(.caption)
            }
        } else {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: ring).stroke(.orange, lineWidth: 3).rotationEffect(.degrees(-90))
                PetFace(species: s?.species ?? "gremlo", row: 14).padding(5)
            }
        }
    }
}
