import FlowBridgeShared
import SwiftUI

/// Sets speaker labels ("Speaker 1:", "Marco:") in semibold accent while the
/// spoken text keeps the container's font. Plain transcripts pass through
/// untouched, so every Text call site can adopt this unconditionally.
enum SpeakerLabelStyler {
    static func attributed(_ text: String) -> AttributedString {
        guard let turns = SpeakerTranscriptFormatter.turns(in: text) else {
            return AttributedString(text)
        }
        var result = AttributedString()
        for (index, turn) in turns.enumerated() {
            var label = AttributedString("\(turn.label): ")
            // Presentation intent (not an explicit font) inherits the
            // surrounding size — the same styler serves the 24pt panel hero
            // and the caption-sized history previews.
            label.inlinePresentationIntent = .stronglyEmphasized
            label.foregroundColor = FlowTheme.accent
            result += label
            result += AttributedString(turn.text)
            if index < turns.count - 1 {
                result += AttributedString("\n\n")
            }
        }
        return result
    }
}
