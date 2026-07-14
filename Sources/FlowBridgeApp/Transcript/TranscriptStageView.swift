import FlowBridgeShared
import SwiftUI

/// ONE stable card that owns the transcript slot for the whole session:
/// live words while recording, the SAME words dimmed under a shimmer while
/// the engine condenses (this kills the old stale-panel flash — the
/// cheapest-feeling moment of the previous build), then the panel with the
/// raw→polished reveal. The container never gets torn down, so height
/// changes animate instead of popping.
struct TranscriptStageView: View {
    let state: FlowBridgeCoordinator.State
    let liveTranscript: LiveTranscriptSnapshot?
    let record: TranscriptRecord?
    let reveal: FlowBridgeCoordinator.PolishReveal?
    var processingStage: FlowBridgeCoordinator.ProcessingStage?
    var vocabularySuggestions: [String] = []
    var suggestedAction: SuggestedAction?
    var actionConfirmation: String?
    var onAddSuggestion: (String) -> Void = { _ in }
    var onDismissSuggestion: (String) -> Void = { _ in }
    var onPerformAction: () -> Void = {}
    var onDismissAction: () -> Void = {}
    var onCopy: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Equatable {
        case streaming
        case condensing
        case settled
    }

    private var phase: Phase {
        switch state {
        case .recording: return .streaming
        case .transcribing: return .condensing
        case .idle, .warming, .ready, .failed: return .settled
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .streaming:
                liveContent(dimmed: false)
            case .condensing:
                // Continuity: the words you just said stay on screen,
                // quieted, while the engine works. Blur is reserved for the
                // reveal — here it's dim + a slow shimmer sweep. Underneath,
                // the pipeline narrates its real micro-stages.
                VStack(alignment: .leading, spacing: FlowTheme.space8) {
                    liveContent(dimmed: true)
                        .overlay {
                            if !reduceMotion {
                                ShimmerSweep()
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.radiusCard, style: .continuous))
                    if let processingStage {
                        Text(processingStage.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FlowTheme.accent)
                            .id(processingStage)
                            // `.blurReplace` is a `Transition`, not an
                            // `AnyTransition` — a plain cross-fade reads
                            // right here and honors Reduce Motion for free.
                            .transition(.opacity)
                    }
                }
                .animation(FlowMotion.state, value: processingStage)
            case .settled:
                TranscriptPanelView(
                    record: record,
                    reveal: reveal,
                    vocabularySuggestions: vocabularySuggestions,
                    suggestedAction: suggestedAction,
                    actionConfirmation: actionConfirmation,
                    onAddSuggestion: onAddSuggestion,
                    onDismissSuggestion: onDismissSuggestion,
                    onPerformAction: onPerformAction,
                    onDismissAction: onDismissAction,
                    onCopy: onCopy
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(FlowTheme.space16)
        .flowCard()
        .animation(FlowMotion.state, value: phase)
    }

    @ViewBuilder
    private func liveContent(dimmed: Bool) -> some View {
        if let snapshot = liveTranscript, !snapshot.text.isEmpty {
            LiveTranscriptView(snapshot: snapshot, frozen: dimmed)
                .frame(maxHeight: 230)
                .opacity(dimmed ? 0.65 : 1)
                .allowsHitTesting(!dimmed)
        } else {
            Text(dimmed ? (processingStage?.label ?? "Refining…") : "Listening…")
                .font(FlowTheme.serifFlavor(17))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        }
    }
}

/// A 60°-tilted highlight translating across the condensing text every
/// 1.1s — time-driven (deterministic), no stored state.
private struct ShimmerSweep: View {
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let progress = t.truncatingRemainder(dividingBy: 1.1) / 1.1
                LinearGradient(
                    colors: [.clear, .white.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * 0.6)
                .offset(x: geo.size.width * (CGFloat(progress) * 1.8 - 0.8))
            }
        }
        .allowsHitTesting(false)
    }
}
