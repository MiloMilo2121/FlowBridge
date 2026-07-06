import FlowBridgeShared
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device transcript cleanup via Apple's FoundationModels (~3B LLM).
///
/// Design rules, in order:
/// 1. The raw transcript is NEVER lost — every failure path (model
///    unavailable, guardrail false positive, context overflow, any error)
///    returns the input unchanged and keeps `rawText` on the record.
/// 2. The polisher cleans, it does not rewrite: fillers out, punctuation and
///    capitalization fixed, words otherwise kept as spoken. Enforced by
///    instructions and greedy sampling.
/// 3. `prewarm()` is called when recording starts so the model is hot by the
///    time the user stops talking.
/// 4. Generation runs OUTSIDE the actor (`polish` is nonisolated): the
///    coordinator abandons a polish that misses its deadline, and
///    FoundationModels does not reliably observe task cancellation — an
///    abandoned generation must not hold the actor hostage and serialize the
///    next dictation's prewarm/polish behind it. The actor only guards the
///    prewarmed-session handoff.
///
/// NOTE: written against the documented iOS 26 FoundationModels API surface;
/// validate against the SDK in Xcode before shipping.
actor TranscriptPolisher {
    static let shared = TranscriptPolisher()

    nonisolated var isEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.polishEnabledKey) as? Bool ?? true
    }

#if canImport(FoundationModels)
    @Generable
    struct PolishedTranscript {
        @Guide(description: "The transcript with filler words removed, punctuation and capitalization corrected, and nothing else changed. Keep the speaker's own words and language.")
        var cleanedText: String
    }

    private var session: LanguageModelSession?

    private static let instructions = """
    You clean up dictation transcripts. Remove filler words (uh, um, ehm, cioè \
    used as filler), fix punctuation, capitalization and obvious \
    transcription spacing artifacts. Do not summarize, do not add content, do \
    not translate, do not change the speaker's wording or language. Return \
    the cleaned transcript only.
    """

    nonisolated var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// The three unavailability modes are distinct user situations and need
    /// distinct explanations — folding them into one "AI unavailable" loses
    /// people (device can't / user turned it off / still downloading).
    nonisolated var availabilityExplanation: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This iPhone doesn't support Apple Intelligence, so transcripts are delivered verbatim."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to enable transcript cleanup."
        case .unavailable(.modelNotReady):
            return "The cleanup model is still downloading; transcripts are delivered verbatim until it's ready."
        case .unavailable:
            return "Transcript cleanup is currently unavailable; transcripts are delivered verbatim."
        }
    }

    /// Loads model weights ahead of the first request. Call when recording
    /// starts; a no-op when the model is unavailable or polishing is off.
    func prewarm() {
        guard isEnabled, isAvailable else { return }
        if session == nil {
            session = LanguageModelSession(instructions: Self.instructions)
        }
        session?.prewarm()
    }

    /// Hands the prewarmed session (if any) to the caller and forgets it —
    /// the only piece of actor state.
    private func takePrewarmedSession() -> LanguageModelSession? {
        defer { session = nil }
        return session
    }

    private static func toneClause(for tone: ToneProfile) -> String {
        switch tone {
        case .neutral:
            return ""
        case .casual:
            return " Target: a chat message — keep it relaxed, drop the trailing period on the final sentence."
        case .formal:
            return " Target: an email or document — complete sentences and standard punctuation."
        }
    }

    /// Returns the polished text, or the input unchanged on any failure.
    /// Nonisolated: the generation itself never blocks the actor (rule 4).
    nonisolated func polish(_ text: String, tone: ToneProfile = .neutral) async -> String {
        guard isEnabled, isAvailable, !text.isEmpty else { return text }

        // One fresh session per transcript: no history accumulation, and the
        // 4096-token window (instructions + input + output) stays predictable.
        // The prewarmed session carries the neutral instructions; tone is
        // appended per call, so a non-neutral tone builds a fresh session.
        let session: LanguageModelSession
        if tone == .neutral, let prewarmed = await takePrewarmedSession() {
            session = prewarmed
        } else {
            session = LanguageModelSession(instructions: Self.instructions + Self.toneClause(for: tone))
        }

        do {
            let response = try await session.respond(
                to: text,
                generating: PolishedTranscript.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let cleaned = response.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? text : cleaned
        } catch {
            // Guardrail false positives, context overflow, model not ready:
            // the dictation always survives as-is.
            return text
        }
    }
#else
    nonisolated var isAvailable: Bool { false }
    nonisolated var availabilityExplanation: String? { "Transcript cleanup requires Apple Intelligence." }
    func prewarm() {}
    nonisolated func polish(_ text: String, tone: ToneProfile = .neutral) async -> String { text }
#endif
}
