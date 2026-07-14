import FlowBridgeShared
import SwiftUI

/// The words as they stream in: one concatenated `Text` (single layout — no
/// per-word views, so re-wraps can never dance), with per-word arrival
/// stamps drawn by `StreamingTextRenderer` at draw time.
///
/// Arrival stamps are assigned by longest-common-prefix diff against the
/// previous snapshot: the normalizer and Whisper can REWRITE earlier words
/// between snapshots, so absolute indices are not stable — only the truly
/// new or rewritten suffix gets fresh stamps while the truly stable prefix
/// keeps its timing.
struct LiveTranscriptView: View {
    let snapshot: LiveTranscriptSnapshot
    /// Condensing: the stage freezes arrivals and the caret.
    var frozen = false

    @State private var displayText = Text(verbatim: "")
    @State private var arrivals: [Date] = []
    @State private var previousWords: [String] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var wordSize: CGFloat = 20

    private static let maxVisibleWords = 120

    var body: some View {
        ScrollView {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 / 20 : 1 / 60, paused: frozen)) { timeline in
                displayText
                    .font(.system(size: wordSize, weight: .medium))
                    .lineSpacing(3)
                    .textRenderer(StreamingTextRenderer(
                        now: timeline.date.timeIntervalSinceReferenceDate,
                        frozen: frozen,
                        reduceMotion: reduceMotion,
                        accent: FlowTheme.accent
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .defaultScrollAnchor(.bottom)
        .onAppear { rebuild() }
        .onChange(of: snapshot.sequence) { _, _ in rebuild() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live transcript")
        .accessibilityValue(snapshot.text)
    }

    /// Rebuilds the memoized Text only when a snapshot lands — the
    /// TimelineView feeds the renderer's clock, never the string.
    private func rebuild() {
        let words = snapshot.text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        let volatileCount = snapshot.previewText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        let now = Date()

        // LCP diff: the unchanged prefix keeps its stamps. Any rewritten or
        // appended suffix receives a fresh arrival, even when word count did
        // not change (the old count-only logic made rewrites appear frozen).
        var commonPrefix = 0
        while commonPrefix < min(words.count, previousWords.count),
              words[commonPrefix] == previousWords[commonPrefix] {
            commonPrefix += 1
        }
        var nextArrivals = Array(arrivals.prefix(commonPrefix))
        if commonPrefix < words.count {
            nextArrivals.append(contentsOf: Array(repeating: now, count: words.count - commonPrefix))
        }
        arrivals = nextArrivals
        previousWords = words

        let start = max(0, words.count - Self.maxVisibleWords)
        var text = Text(verbatim: "")
        for index in start..<words.count {
            let piece = (index > start ? " " : "") + words[index]
            let stampedWord = Text(verbatim: piece)
                .customAttribute(WordStampAttribute(
                    arrival: arrivals[index],
                    isVolatile: index >= words.count - volatileCount
                ))
            text = Text("\(text)\(stampedWord)")
        }
        displayText = text
    }
}
