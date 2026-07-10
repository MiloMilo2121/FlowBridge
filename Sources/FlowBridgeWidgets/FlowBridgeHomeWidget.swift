import AppIntents
import FlowBridgeShared
import SwiftUI
import WidgetKit

/// Home Screen widget: capture button plus the latest transcript.
struct FlowBridgeHomeWidget: Widget {
    static let kind = "com.marcomilanello.flowbridge.widget.home"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LatestTranscriptProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FlowBridge")
        .description("Start dictating and see your latest transcript.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LatestTranscriptEntry: TimelineEntry {
    let date: Date
    let transcript: String?
}

struct LatestTranscriptProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestTranscriptEntry {
        LatestTranscriptEntry(date: Date(), transcript: "Your last dictation shows up here.")
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestTranscriptEntry) -> Void) {
        completion(LatestTranscriptEntry(date: Date(), transcript: TranscriptStore.latest()?.text))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestTranscriptEntry>) -> Void) {
        let entry = LatestTranscriptEntry(date: Date(), transcript: TranscriptStore.latest()?.text)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

private struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LatestTranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(intent: StartDictationIntent()) {
                Label("Dictate", systemImage: "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(FlowBridgeTheme.flowViolet)

            if family == .systemMedium {
                Text(entry.transcript ?? "No dictations yet.")
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(entry.transcript == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
