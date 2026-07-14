import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button control: one tap starts
/// dictation through `StartDictationIntent` (background start with the Live
/// Activity as the visible surface; foreground fallback otherwise).
struct DictationControlWidget: ControlWidget {
    static let kind = "com.marcomilanello.flowbridge.control.dictate"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartDictationIntent()) {
                Label("Speak", systemImage: "waveform.path")
            }
        }
        .displayName("FlowBridge Dictation")
        .description("Start the live voice bridge with one tap.")
    }
}
