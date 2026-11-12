import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct NotchiWidgets: WidgetBundle {
    var body: some Widget { StatusWidget(); RunActivity() }
}

struct Entry: TimelineEntry { let date: Date; let state: PhoneState? }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), state: nil) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date(), state: Store.state)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date(), state: Store.state)], policy: .after(Date().addingTimeInterval(900))))
    }
}

/// Today: the pet, its mood and the run; agents waiting; asleep after hours.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "status", provider: Provider()) { e in
            StatusView(e: e).containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Notchi").description("Your pet, its run, and what's waiting on you.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct StatusView: View {
    let e: Entry
    var body: some View {
        if let s = e.state {
            let asleep = afterHours(e.date) && !s.running
            HStack(spacing: 10) {
                PetFace(species: s.species, row: asleep ? 26 : (s.waiting.isEmpty ? 5 : 7)).frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.headline).foregroundStyle(.white)
                    Text(asleep ? "asleep" : s.running ? "\(s.tools) tools" : s.mood).font(.caption).foregroundStyle(.white.opacity(0.6))
                    if !s.waiting.isEmpty { Text("\(s.waiting.count) waiting on you").font(.caption.bold()).foregroundStyle(.orange) }
                }
            }
        } else {
            Text("Pair Notchi with your Mac").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }
}

struct RunActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunAttributes.self) { ctx in
            LockView(ctx: ctx).padding().activityBackgroundTint(.black)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { PetFace(species: ctx.attributes.species, row: 14).frame(width: 40) }
                DynamicIslandExpandedRegion(.trailing) { Text(ctx.attributes.startedAt, style: .timer).monospacedDigit().frame(width: 60) }
                DynamicIslandExpandedRegion(.bottom) { AskView(state: ctx.state) }
            } compactLeading: {
                PetFace(species: ctx.attributes.species, row: 14).frame(width: 22)
            } compactTrailing: {
                Text(ctx.attributes.startedAt, style: .timer).monospacedDigit().frame(width: 44)
            } minimal: {
                PetFace(species: ctx.attributes.species, row: ctx.state.waitingCount > 0 ? 7 : 14).frame(width: 20)
            }
        }
    }
}

struct LockView: View {
    let ctx: ActivityViewContext<RunAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PetFace(species: ctx.attributes.species, row: 14).frame(width: 32)
                Text(ctx.attributes.name).font(.headline).foregroundStyle(.white)
                Spacer()
                Text(ctx.attributes.startedAt, style: .timer).monospacedDigit().foregroundStyle(.white)
            }
            AskView(state: ctx.state)
        }
    }
}

/// The approval on the lock screen and in the Dynamic Island. Allow asks for Face ID (AnswerIntent).
struct AskView: View {
    let state: RunAttributes.ContentState
    var body: some View {
        if let id = state.waitingId {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(state.waitingTool ?? "tool"): \(state.waitingSummary ?? "")").font(.caption.monospaced()).lineLimit(2).foregroundStyle(.white)
                if state.waitingRisky {
                    Text("Open on the Mac").font(.caption.bold()).foregroundStyle(.orange)
                } else {
                    HStack {
                        Button(intent: AnswerIntent(id: id, allow: false)) { Text("Deny") }.tint(.red)
                        Button(intent: AnswerIntent(id: id, allow: true)) { Text("Allow once") }.tint(.green)
                    }
                }
            }
        } else {
            Text("\(state.tools) tools · \(state.mood)").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
    }
}
