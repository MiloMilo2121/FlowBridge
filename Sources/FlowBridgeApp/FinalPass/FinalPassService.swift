import FlowBridgeShared
import Foundation

/// The final-pass provider: which engine re-transcribes the full session
/// audio after stop. Streaming quality is bounded by chunked decoding; one
/// full-context pass is what offline WER benchmarks measure.
enum FinalPassMode: String, CaseIterable {
    case off
    case localPrecision
    case cloudScribe

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .localPrecision: return "On-device Enhanced"
        case .cloudScribe: return "ElevenLabs cloud"
        }
    }

    static var current: FinalPassMode {
        let defaults = try? SharedContainer.userDefaults()
        if let raw = defaults?.string(forKey: FlowBridgeConstants.finalPassModeKey),
           let mode = FinalPassMode(rawValue: raw) {
            return mode
        }
        // Migration from the short-lived bool toggle.
        if let legacy = defaults?.object(forKey: FlowBridgeConstants.finalPassEnabledKey) as? Bool {
            return legacy ? .localPrecision : .off
        }
        return .localPrecision
    }

    static func set(_ mode: FinalPassMode) {
        let defaults = try? SharedContainer.userDefaults()
        defaults?.set(mode.rawValue, forKey: FlowBridgeConstants.finalPassModeKey)
    }
}

/// Engine-agnostic final pass over the session's safety-buffer WAV: works
/// identically above Whisper, Apple Speech, and (tomorrow) the realtime
/// cloud stream. Provider cascade: cloud → local precision → streamed
/// fallback; the delivered text can only get better, never lost.
@MainActor
final class FinalPassService {
    private var engines: [WhisperModelVariant: WhisperEngine] = [:]
    /// Set once a sideloaded Precision model has produced nothing usable —
    /// later takes this app session skip straight to the bundled model
    /// instead of repeating the same failed (or hallucinated) decode.
    private var precisionKnownBroken = false

    private func engine(for variant: WhisperModelVariant) -> WhisperEngine {
        if let engine = engines[variant] { return engine }
        let engine = WhisperEngine(variant: variant)
        engines[variant] = engine
        return engine
    }

    /// Returns the refined text, or `fallback` untouched when the pass is
    /// off, ineligible, or failed. Cleans up the session audio file unless
    /// it must survive for next-launch recovery.
    func refine(
        sessionID: UUID,
        duration: TimeInterval,
        fallback: String,
        forceLocalRefinement: Bool = false
    ) async -> String {
        guard let url = Self.safetyFileURL(sessionID: sessionID),
              FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }

        var mode = FinalPassMode.current
        let speakers = SpeakerDetection.isEnabled
        // Enhanced streaming and diarization both need the complete recording
        // pass even when the standalone Final Pass picker is Off.
        if mode == .off,
           LocalWhisperRuntimePlan.shouldRunLocalFinalPass(
               configured: false,
               precisionRequested: forceLocalRefinement,
               speakerDetection: speakers
           ) {
            mode = .localPrecision
        }
        let eligible = duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds
            && duration <= FlowBridgeConstants.finalPassMaxSeconds

        var refined: String?
        if eligible {
            switch mode {
            case .off:
                break
            case .localPrecision:
                refined = await localRefine(url: url, duration: duration, speakers: speakers)
            case .cloudScribe:
                refined = await cloudRefine(url: url, duration: duration, speakers: speakers)
                if refined == nil {
                    FBLog.log("finalpass: cloud failed, cascading to local precision")
                    refined = await localRefine(url: url, duration: duration, speakers: speakers)
                }
            }
        }

        let text = (refined?.isEmpty == false) ? refined! : fallback
        // Keep the WAV only when we produced nothing at all and the audio is
        // long enough for a next-launch recovery attempt.
        if !(text.isEmpty && duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds) {
            try? FileManager.default.removeItem(at: url)
        }
        // A Foundation Models polish may run immediately after this method.
        // Release every Core ML transcription model first instead of keeping
        // a second engine cache alive for the next take.
        await unloadEngines()
        return text
    }

    private func unloadEngines() async {
        let loaded = Array(engines.values)
        engines.removeAll()
        for engine in loaded {
            await engine.unload()
        }
    }

    private func cloudRefine(url: URL, duration: TimeInterval, speakers: Bool) async -> String? {
        guard CloudCredentialsStore.hasKey else {
            FBLog.log("finalpass: cloud selected but no API key")
            return nil
        }
        FBLog.log("finalpass: cloud pass (\(Int(duration))s audio\(speakers ? ", diarized" : ""))")
        return try? await CloudScribeClient
            .transcribe(fileURL: url, language: DictationLanguage.current, diarize: speakers)
            .bestText
    }

    private func localRefine(url: URL, duration: TimeInterval, speakers: Bool) async -> String? {
        // Segments are engine-independent, so diarize once up front and share
        // the result across model attempts. Serializing diarizer and Whisper
        // also keeps them from contending for the Neural Engine.
        var segments: [SpeakerTranscriptFormatter.Segment] = []
        if speakers, LocalDiarizer.isAvailable {
            segments = (try? await LocalDiarizer.shared.diarize(url: url)) ?? []
            // `diarize` also releases on every exit; this explicit call makes
            // the handoff invariant visible and remains idempotent.
            await LocalDiarizer.shared.unload()
        } else if speakers {
            FBLog.log("finalpass: speakers on but diarization models not bundled")
        }

        let planned = LocalWhisperRuntimePlan.finalModel(
            precisionInstalled: WhisperModelLocator.precisionFolderIfInstalled() != nil,
            precisionValidated: PrecisionRuntimePolicy.installedArtifactValidated
        )
        var preferred: WhisperModelVariant = planned == .precision ? .precision : .bundled
        if preferred == .precision, precisionKnownBroken {
            preferred = .bundled
        }
        if let text = await localAttempt(variant: preferred, url: url, duration: duration, segments: segments) {
            return text
        }

        // A sideloaded precision model can be broken in ways the bundled one
        // never is (bad ANE compile, corrupt weights) — it then decodes to
        // empty, or hallucinates plausible-looking garbage, on every take.
        // The bundled model is the known-good floor: retry there rather than
        // dropping to the streamed text, and remember the verdict so later
        // takes this session skip the failing model entirely.
        guard preferred == .precision else { return nil }
        FBLog.log("finalpass: precision produced nothing usable, retrying with bundled model")
        precisionKnownBroken = true
        await engines[.precision]?.unload()
        return await localAttempt(variant: .bundled, url: url, duration: duration, segments: segments)
    }

    private func localAttempt(
        variant: WhisperModelVariant,
        url: URL,
        duration: TimeInterval,
        segments: [SpeakerTranscriptFormatter.Segment]
    ) async -> String? {
        let engine = engine(for: variant)
        let recording = RecordedAudio(url: url, duration: duration)

        if !segments.isEmpty {
            FBLog.log("finalpass: local diarized pass (\(Int(duration))s audio, \(variant))")
            // Words meet segments at their midpoints. Any failure degrades to
            // the flat text — never a lost dictation.
            if let transcription = try? await engine.transcribeWithWords(recording: recording),
               !Self.looksHallucinated(transcription.text) {
                if !transcription.words.isEmpty {
                    let labeled = SpeakerTranscriptFormatter.labeledText(
                        words: SpeakerTranscriptFormatter.assign(words: transcription.words, to: segments)
                    )
                    if !labeled.isEmpty {
                        return labeled
                    }
                }
                FBLog.log("finalpass: diarizer produced nothing usable, keeping flat text")
                return transcription.text
            }
            FBLog.log("finalpass: word-level pass failed, falling back to plain pass")
        }

        FBLog.log("finalpass: local pass (\(Int(duration))s audio, \(variant))")
        let started = Date()
        let record = try? await engine.transcribe(recording: recording, source: .microphone)
        FBLog.log("finalpass: local \(record == nil ? "failed" : "ok \(record!.text.count)ch") in \(Int(Date().timeIntervalSince(started)))s")
        guard let text = record?.text, !Self.looksHallucinated(text) else {
            if record != nil {
                FBLog.log("finalpass: local pass looked hallucinated, discarding")
            }
            return nil
        }
        return text
    }

    /// A model with corrupted weights or a broken ANE compile doesn't always
    /// fail cleanly — it can hallucinate plausible-looking text from silence
    /// (the documented symptom on this app: "I love you." repeated hundreds
    /// of times). A short phrase dominating the output is that signature,
    /// not a real dictation, so it's treated the same as no result at all.
    private static func looksHallucinated(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count >= 12 else { return false }
        var counts: [Substring: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        let mostCommon = counts.values.max() ?? 0
        return Double(mostCommon) / Double(words.count) > 0.4
    }

    static func safetyFileURL(sessionID: UUID) -> URL? {
        guard let directory = try? AudioSafetyBuffer.defaultDirectory() else { return nil }
        return directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension("wav")
    }
}
