import FlowBridgeShared
import SwiftUI

/// The words as they stream in: committed words in primary, the volatile
/// tail in secondary, each new word arriving with a fade+rise. Engine
/// snapshots are whole strings (no word events), so word identity comes from
/// the absolute position in the text — SwiftUI then animates only the
/// appended tail.
struct LiveTranscriptView: View {
    let snapshot: LiveTranscriptSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var wordSize: CGFloat = 20

    private static let maxVisibleWords = 60

    var body: some View {
        ScrollView {
            FlowLayout(spacing: 6, lineSpacing: 8) {
                ForEach(visibleWords) { word in
                    Text(word.text)
                        .font(.system(size: wordSize, weight: .medium))
                        .foregroundStyle(word.isVolatile ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(FlowMotion.state, value: visibleWords.count)
        }
        .defaultScrollAnchor(.bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live transcript")
        .accessibilityValue(snapshot.text)
    }

    private struct Word: Identifiable {
        /// Absolute index in the full transcript: earlier words keep their
        /// identity as new ones append, so only the tail animates in.
        let id: Int
        let text: String
        let isVolatile: Bool
    }

    private var visibleWords: [Word] {
        let all = snapshot.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let volatileCount = snapshot.previewText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        let start = max(0, all.count - Self.maxVisibleWords)
        return (start..<all.count).map { index in
            Word(
                id: index,
                text: String(all[index]),
                isVolatile: index >= all.count - volatileCount
            )
        }
    }
}

/// Minimal left-to-right wrapping layout for the streaming words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(
            width: maxWidth == .infinity ? usedWidth : maxWidth,
            height: y + lineHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
