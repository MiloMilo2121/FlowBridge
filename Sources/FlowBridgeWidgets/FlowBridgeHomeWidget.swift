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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path")
                    .foregroundStyle(FlowBridgeTheme.accentGradient)
                Text("FlowBridge")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("READY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }

            if family == .systemMedium {
                HStack(spacing: 12) {
                    captureButton
                        .frame(width: 126)
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LATEST")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(entry.transcript ?? "Your next words will settle here.")
                            .font(.caption.weight(entry.transcript == nil ? .regular : .medium))
                            .lineLimit(4)
                            .foregroundStyle(entry.transcript == nil ? .secondary : .primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Spacer(minLength: 0)
                captureButton
                Spacer(minLength: 0)
            }
        }
    }

    private var captureButton: some View {
        Button(intent: StartDictationIntent()) {
            VStack(spacing: 8) {
                FlowWaveShape(
                    levels: [0.12, 0.2, 0.5, 0.86, 0.54, 0.28, 0.18],
                    controlPoints: 11
                )
                .fill(FlowBridgeTheme.accentGradient)
                .frame(height: 24)
                Label("Speak", systemImage: "mic.fill")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(FlowBridgeTheme.flowViolet)
    }
}
