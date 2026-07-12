import FlowBridgeShared
import SwiftUI

/// The latest transcript, and the payoff moment: when a take was polished,
/// the panel first shows the verbatim words (visual continuity with the live
/// stream), then — a beat later — blur-morphs into the polished text with a
/// "N words cleaned" caption. Tapping the caption compares raw and polished.
struct TranscriptPanelView: View {
    let record: TranscriptRecord?
    let reveal: FlowBridgeCoordinator.PolishReveal?
    var vocabularySuggestions: [String] = []
    var onAddSuggestion: (String) -> Void = { _ in }
    var onDismissSuggestion: (String) -> Void = { _ in }

    @State private var showRaw = false
    @State private var captionVisible = false
    @ScaledMetric(relativeTo: .title2) private var heroSize: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: FlowTheme.space12) {
            HStack {
                Text(showRaw && captionVisible ? "Verbatim" : "Latest")
                    .font(.headline)
                    .contentTransition(.opacity)
                Spacer()
                if let record {
                    Text(record.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                Text(displayText)
                    .font(.system(size: heroSize))
                    .textSelection(.enabled)
                    .foregroundStyle(record == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .id(showRaw)
                    .revealTransition(reduceMotion: reduceMotion)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)

            if let reveal, captionVisible {
                Button {
                    withAnimation(FlowMotion.state) {
                        showRaw.toggle()
                    }
                } label: {
                    HStack(spacing: FlowTheme.space4) {
                        Image(systemName: "sparkles")
                        Text(captionText(for: reveal))
                            .contentTransition(.numericText())
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FlowTheme.accent)
                }
                .buttonStyle(FlowPressButtonStyle())
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            if !vocabularySuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.space8) {
                        ForEach(vocabularySuggestions, id: \.self) { word in
                            suggestionChip(word)
                        }
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .padding(FlowTheme.space16)
        .flowCard()
        .animation(FlowMotion.state, value: vocabularySuggestions)
        .onChange(of: reveal) { _, newReveal in
            runReveal(newReveal)
        }
    }

    /// One tap teaches the app a word it stumbled on — no menu digging.
    private func suggestionChip(_ word: String) -> some View {
        HStack(spacing: FlowTheme.space4) {
            Button {
                onAddSuggestion(word)
            } label: {
                Label(word, systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .buttonStyle(FlowPressButtonStyle())

            Button {
                onDismissSuggestion(word)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(word)")
        }
        .padding(.horizontal, FlowTheme.space8)
        .padding(.vertical, FlowTheme.space4)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .foregroundStyle(FlowTheme.accent)
    }

    private var displayText: String {
        if showRaw, let reveal {
            return reveal.raw
        }
        return record?.text ?? " "
    }

    private func captionText(for reveal: FlowBridgeCoordinator.PolishReveal) -> String {
        if showRaw {
            return "verbatim — tap for polished"
        }
        if reveal.wordsDelta > 0 {
            return "\(reveal.wordsDelta) words cleaned — tap to compare"
        }
        return "polished — tap to compare"
    }

    /// The reveal beat: verbatim first (continuity with the live words),
    /// then the polished text morphs in.
    private func runReveal(_ reveal: FlowBridgeCoordinator.PolishReveal?) {
        guard reveal != nil else {
            showRaw = false
            captionVisible = false
            return
        }

        showRaw = true
        captionVisible = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(reduceMotion ? FlowMotion.state : .smooth(duration: 0.55)) {
                showRaw = false
                captionVisible = true
            }
        }
    }
}

private extension View {
    /// `.blurReplace` is a `Transition`, not an `AnyTransition`, so it can't
    /// share a ternary with `.opacity`. A @ViewBuilder branch keeps the blur
    /// for the reveal while honoring Reduce Motion with a plain cross-fade.
    @ViewBuilder
    func revealTransition(reduceMotion: Bool) -> some View {
        if reduceMotion {
            transition(.opacity)
        } else {
            transition(.blurReplace)
        }
    }
}
