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
                        FlowWaveShape(
                            levels: [0.12, 0.34, 0.85, 0.42, 0.16],
                            controlPoints: 7
                        )
                        .fill(.tint)
                        .frame(width: 34, height: 22)
                    }
                }
                .buttonStyle(.plain)
            default:
                Button(intent: StartDictationIntent()) {
                    HStack(spacing: 8) {
                        FlowWaveShape(
                            levels: [0.1, 0.28, 0.78, 0.46, 0.16],
                            controlPoints: 7
                        )
                        .fill(.tint)
                        .frame(width: 34, height: 20)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Speak")
                                .font(.headline)
                            Text("Opens the live bridge")
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
        .widgetAccentable()
        .accessibilityLabel("Start dictation")
    }
}
