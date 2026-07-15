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
/// 3. Foundation Models is never prewarmed while a speech model owns the
///    microphone. Loading both model families together exceeds the device's
///    safe memory envelope; the coordinator hands memory over at stop.
///
/// NOTE: written against the documented iOS 26 FoundationModels API surface;
/// validate against the SDK in Xcode before shipping.
actor TranscriptPolisher {
    static let shared = TranscriptPolisher()
    private static let responseBudget: Duration = .seconds(8)

    var isEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.polishEnabledKey) as? Bool ?? true
    }

#if canImport(FoundationModels)
    @Generable
    struct PolishedTranscript {
        @Guide(description: "The transcript with filler words removed, punctuation and capitalization corrected, and nothing else changed. MUST be in the exact same language as the input transcript — never translated.")
        var cleanedText: String
    }

    private var session: LanguageModelSession?

    private static let instructions = """
    You clean up dictation transcripts. Remove filler words (uh, um, ehm, cioè \
    used as filler), fix punctuation, capitalization and obvious \
    transcription spacing artifacts. Do not summarize, do not add content, do \
    not change the speaker's wording. CRITICAL: the output stays in the exact \
    language the transcript was spoken in — translating it is a failure, even \
    if the rest of the conversation is in another language. Return the \
    cleaned transcript only.
    """

    /// A per-request language pin: the ~3B model happily "helps" by
    /// translating into the system language unless told, in the prompt
    /// itself, that the transcript language is the output language.
    private static func languageClause() -> String {
        switch DictationLanguage.current {
        case .auto:
            return "Reply in the same language as the transcript below."
        case .italian:
            return "The transcript below is Italian. The cleaned text must be Italian."
        case .english:
            return "The transcript below is English. The cleaned text must be English."
        }
    }

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Optional idle-only warmup. Never call this while Whisper or the local
    /// diarizer is resident; model families are intentionally serialized.
    func prewarm() {
        guard isEnabled, isAvailable else { return }
        if session == nil {
            session = LanguageModelSession(instructions: Self.instructions)
        }
        session?.prewarm()
    }

    /// Drops an unused prewarmed session before speech recognition begins or
    /// when iOS reports pressure. An in-flight response remains actor-ordered
    /// and completes before this executes, preventing a model overlap race.
    func releaseSession() {
        session = nil
    }

    private static func toneClause(for tone: ToneProfile) -> String {
        switch tone {
        case .neutral:
            return ""
        case .casual:
            return " Target: a chat message — keep it relaxed, drop the trailing period on the final sentence."
        case .formal:
            return " Target: an email or document — complete sentences and standard punctuation."
        case .concise:
            return " Target: tighter — compress the phrasing, drop redundancies and hedges, keep every fact and the language."
        }
    }

    /// Returns the polished text, or the input unchanged on any failure.
    func polish(_ text: String, tone: ToneProfile = .neutral) async -> String {
        guard isEnabled, isAvailable, !text.isEmpty else { return text }

        // One fresh session per transcript: no history accumulation, and the
        // 4096-token window (instructions + input + output) stays predictable.
        // The prewarmed session carries the neutral instructions; tone is
        // appended per call, so a non-neutral tone builds a fresh session.
        let session: LanguageModelSession
        if tone == .neutral, let prewarmed = self.session {
            session = prewarmed
        } else {
            session = LanguageModelSession(instructions: Self.instructions + Self.toneClause(for: tone))
        }
        self.session = nil

        let maximumTokens = min(
            2_048,
            max(128, text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count * 3)
        )
        FBLog.log("polish: begin (\(text.count)ch, budget=8s)")
        let generation = Task<String, Never> {
            do {
                let response = try await session.respond(
                    to: Self.languageClause() + "\n\n" + text,
                    generating: PolishedTranscript.self,
                    options: GenerationOptions(
                        sampling: .greedy,
                        maximumResponseTokens: maximumTokens
                    )
                )
                let cleaned = response.content.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? text : cleaned
            } catch {
                // Guardrail false positives, context overflow, model not
                // ready, or cancellation: the dictation survives as-is.
                return text
            }
        }

        let outcome = await TaskDeadline.value(
            from: generation,
            fallback: text,
            after: Self.responseBudget
        )
        if outcome.timedOut {
            FBLog.log("polish: timed out, keeping verbatim")
        } else {
            FBLog.log("polish: completed (\(outcome.value.count)ch)")
        }
        return outcome.value
    }
#else
    var isAvailable: Bool { false }
    func prewarm() {}
    func releaseSession() {}
    func polish(_ text: String, tone: ToneProfile = .neutral) async -> String { text }
#endif
}
