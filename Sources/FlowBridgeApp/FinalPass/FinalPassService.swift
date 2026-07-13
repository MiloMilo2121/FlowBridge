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
        case .localPrecision: return "On-device Precision"
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
    private var precisionEngine: WhisperEngine?

    /// Returns the refined text, or `fallback` untouched when the pass is
    /// off, ineligible, or failed. Cleans up the session audio file unless
    /// it must survive for next-launch recovery.
    func refine(sessionID: UUID, duration: TimeInterval, fallback: String) async -> String {
        guard let url = Self.safetyFileURL(sessionID: sessionID),
              FileManager.default.fileExists(atPath: url.path) else {
            return fallback
        }

        var mode = FinalPassMode.current
        let speakers = SpeakerDetection.isEnabled
        // Diarization lives in the final pass: with the pass off it quietly
        // borrows the on-device Precision pass (the Settings footer says so).
        if speakers && mode == .off {
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
        return text
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
        let engine: WhisperEngine
        if let precisionEngine {
            engine = precisionEngine
        } else {
            let variant: WhisperModelVariant = WhisperModelLocator.precisionFolderIfInstalled() != nil ? .precision : .bundled
            engine = WhisperEngine(variant: variant)
            precisionEngine = engine
        }

        let recording = RecordedAudio(url: url, duration: duration)

        if speakers, LocalDiarizer.isAvailable {
            FBLog.log("finalpass: local diarized pass (\(Int(duration))s audio)")
            // Diarizer (ANE) and Whisper run concurrently over the same WAV;
            // words meet segments at their midpoints. Any failure degrades
            // to the flat precision text — never a lost dictation.
            async let segmentsTask = LocalDiarizer.shared.diarize(url: url)
            async let wordsTask = engine.transcribeWithWords(recording: recording)
            let segments = (try? await segmentsTask) ?? []
            let transcription = try? await wordsTask
            if let transcription {
                if !segments.isEmpty, !transcription.words.isEmpty {
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
        } else if speakers {
            FBLog.log("finalpass: speakers on but diarization models not bundled")
        }

        FBLog.log("finalpass: local pass (\(Int(duration))s audio)")
        let started = Date()
        let record = try? await engine.transcribe(recording: recording, source: .microphone)
        FBLog.log("finalpass: local \(record == nil ? "failed" : "ok \(record!.text.count)ch") in \(Int(Date().timeIntervalSince(started)))s")
        return record?.text
    }

    static func safetyFileURL(sessionID: UUID) -> URL? {
        guard let directory = try? AudioSafetyBuffer.defaultDirectory() else { return nil }
        return directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension("wav")
    }
}
