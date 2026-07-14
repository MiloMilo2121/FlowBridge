import FlowBridgeShared
import SwiftUI
import WidgetKit

/// Lock Screen entry point: one tap and dictation starts in the background —
/// the Dynamic Island picks up the session, the app never has to open. Same
/// `AudioRecordingIntent` path the Control Center button uses.
struct SpeakLockWidget: Widget {
    static let kind = "com.marcomilanello.flowbridge.widget.speak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SpeakProvider()) { _ in
            SpeakLockView()
        }
        .configurationDisplayName("Speak")
        .description("Start dictation straight from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct SpeakEntry: TimelineEntry {
    let date: Date
}

private struct SpeakProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpeakEntry {
        SpeakEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SpeakEntry) -> Void) {
        completion(SpeakEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpeakEntry>) -> Void) {
        completion(Timeline(entries: [SpeakEntry(date: Date())], policy: .never))
    }
}

private struct SpeakLockView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: StartDictationIntent()) {
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: "mic.fill")
                            .font(.title3.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            default:
                Button(intent: StartDictationIntent()) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Speak")
                                .font(.headline)
                            Text("FlowBridge")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel("Start dictation")
    }
}
