import FlowBridgeShared
import Foundation

enum EnginePreference: String, CaseIterable {
    /// WhisperKit with the bundled model, the V1 default. Stays the default
    /// until the Apple engine wins on our own benchmark set.
    case whisper
    /// WhisperKit with the optional higher-accuracy model installed under
    /// Application Support (falls back to bundled when absent).
    case whisperPrecision
    /// iOS 26 SpeechAnalyzer/SpeechTranscriber (system model, opt-in).
    case appleSpeech
    /// Opt-in cloud provider (OFF by default; audio leaves the device only
    /// while this is both enabled and selected).
    case cloud

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (bundled)"
        case .whisperPrecision: return "Whisper Precision"
        case .appleSpeech: return "Apple Speech"
        case .cloud: return "Cloud (\(FlowBridgeConstants.cloudProviderName))"
        }
    }

    static var current: EnginePreference {
        let defaults = try? SharedContainer.userDefaults()
        let raw = defaults?.string(forKey: FlowBridgeConstants.preferredEngineKey)
        return raw.flatMap(EnginePreference.init(rawValue:)) ?? .whisper
    }

    static func set(_ preference: EnginePreference) {
        let defaults = try? SharedContainer.userDefaults()
        defaults?.set(preference.rawValue, forKey: FlowBridgeConstants.preferredEngineKey)
    }
}

enum EngineFactory {
    struct Built {
        let engine: any TranscriptionEngine
        /// The preference actually satisfied — `.whisper` whenever the
        /// request had to fall back. Callers record this, not the requested
        /// preference, so the user can be told which engine is really
        /// running.
        let resolved: EnginePreference
    }

    /// The preference that `requested` can actually be satisfied with right
    /// now, without building anything. A fallback is re-resolved on every
    /// start so a fix (cloud key added, locale supported) is picked up,
    /// while an unchanged fallback is not rebuilt.
    static func resolve(_ requested: EnginePreference) async -> EnginePreference {
        switch requested {
        case .whisper:
            return .whisper
        case .whisperPrecision:
            // The requested variant falls back to the bundled model, but
            // the preference is still honored: the user asked for Whisper
            // either way, and no engine change is worth reporting.
            return .whisperPrecision
        case .appleSpeech:
            // Apple's transcriber only exists for supported locales; without
            // this guard the selection fails at runtime mid-dictation.
            return await AppleSpeechEngine.isUsable() ? .appleSpeech : .whisper
        case .cloud:
            // The cloud engine only exists while explicitly enabled AND
            // configured; anything less falls back to fully local.
            return CloudGate.isCloudEngineEnabled && KeychainStore.loadCloudAPIKey() != nil
                ? .cloud
                : .whisper
        }
    }

    static func make(_ resolved: EnginePreference) -> Built {
        switch resolved {
        case .whisper:
            return Built(engine: WhisperEngine(), resolved: .whisper)
        case .whisperPrecision:
            let variant: WhisperModelVariant = WhisperModelLocator.precisionFolderIfInstalled() != nil
                ? .precision
                : .bundled
            return Built(engine: WhisperEngine(variant: variant), resolved: .whisperPrecision)
        case .appleSpeech:
            return Built(engine: AppleSpeechEngine(), resolved: .appleSpeech)
        case .cloud:
            return Built(engine: CloudEngine(), resolved: .cloud)
        }
    }
}
