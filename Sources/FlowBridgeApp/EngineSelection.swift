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

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (bundled)"
        case .whisperPrecision: return "Whisper Precision"
        case .appleSpeech: return "Apple Speech"
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
    static func makeCurrent() -> any TranscriptionEngine {
        switch EnginePreference.current {
        case .whisper:
            return WhisperEngine()
        case .whisperPrecision:
            if WhisperModelLocator.precisionFolderIfInstalled() != nil {
                return WhisperEngine(variant: .precision)
            }
            return WhisperEngine()
        case .appleSpeech:
            return AppleSpeechEngine()
        }
    }
}
