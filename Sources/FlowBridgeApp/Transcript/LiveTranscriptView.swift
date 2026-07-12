import FlowBridgeShared
import SwiftUI

/// The words as they stream in: committed words in primary, the volatile
/// tail in secondary. Rendered as ONE attributed Text — per-word views made
/// the block "dance": every re-transcription of the volatile tail changed
/// word widths and re-wrapped the whole layout. A single Text wraps
/// naturally and only ever grows.
struct LiveTranscriptView: View {
    let snapshot: LiveTranscriptSnapshot

    @ScaledMetric(relativeTo: .title3) private var wordSize: CGFloat = 20

    /// Older words scroll away; capping keeps the attributed rebuild cheap
    /// at streaming cadence.
    private static let maxVisibleWords = 120

    var body: some View {
        ScrollView {
            Text(attributedTranscript)
                .font(.system(size: wordSize, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live transcript")
        .accessibilityValue(snapshot.text)
    }

    private var attributedTranscript: AttributedString {
        let words = snapshot.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let volatileCount = snapshot.previewText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        let visible = words.suffix(Self.maxVisibleWords)
        let committedCount = max(0, visible.count - volatileCount)

        var committed = AttributedString(visible.prefix(committedCount).joined(separator: " "))
        committed.foregroundColor = .primary

        guard visible.count > committedCount else { return committed }

        var volatile = AttributedString(
            (committedCount > 0 ? " " : "") + visible.suffix(visible.count - committedCount).joined(separator: " ")
        )
        volatile.foregroundColor = .secondary
        return committed + volatile
    }
}
