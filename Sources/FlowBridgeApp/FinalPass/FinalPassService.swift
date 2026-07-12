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

        let mode = FinalPassMode.current
        let eligible = duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds
            && duration <= FlowBridgeConstants.finalPassMaxSeconds

        var refined: String?
        if eligible {
            switch mode {
            case .off:
                break
            case .localPrecision:
                refined = await localRefine(url: url, duration: duration)
            case .cloudScribe:
                refined = await cloudRefine(url: url, duration: duration)
                if refined == nil {
                    FBLog.log("finalpass: cloud failed, cascading to local precision")
                    refined = await localRefine(url: url, duration: duration)
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

    private func cloudRefine(url: URL, duration: TimeInterval) async -> String? {
        guard CloudCredentialsStore.hasKey else {
            FBLog.log("finalpass: cloud selected but no API key")
            return nil
        }
        FBLog.log("finalpass: cloud pass (\(Int(duration))s audio)")
        return try? await CloudScribeClient
            .transcribe(fileURL: url, language: DictationLanguage.current)
            .text
    }

    private func localRefine(url: URL, duration: TimeInterval) async -> String? {
        let engine: WhisperEngine
        if let precisionEngine {
            engine = precisionEngine
        } else {
            let variant: WhisperModelVariant = WhisperModelLocator.precisionFolderIfInstalled() != nil ? .precision : .bundled
            engine = WhisperEngine(variant: variant)
            precisionEngine = engine
        }

        FBLog.log("finalpass: local pass (\(Int(duration))s audio)")
        let started = Date()
        let record = try? await engine.transcribe(
            recording: RecordedAudio(url: url, duration: duration),
            source: .microphone
        )
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
