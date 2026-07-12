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
    /// ElevenLabs Scribe v2 Realtime over websocket — explicit cloud opt-in.
    case cloudRealtime

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (bundled)"
        case .whisperPrecision: return "Whisper Precision"
        case .appleSpeech: return "Apple Speech"
        case .cloudRealtime: return "ElevenLabs Realtime (cloud)"
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

/// The dictation language hint. Pinning it (instead of per-chunk
/// auto-detect) is the single cheapest accuracy win on streaming Whisper;
/// the Apple engine uses it as its transcriber locale.
enum DictationLanguage: String, CaseIterable {
    case auto
    case italian = "it"
    case english = "en"

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .italian: return "Italiano"
        case .english: return "English"
        }
    }

    /// Whisper decoding language code; nil lets the model detect.
    var whisperCode: String? {
        self == .auto ? nil : rawValue
    }

    /// Locale for the Apple Speech transcriber; nil falls back to system.
    var speechLocale: Locale? {
        switch self {
        case .auto: return nil
        case .italian: return Locale(identifier: "it-IT")
        case .english: return Locale(identifier: "en-US")
        }
    }

    static var current: DictationLanguage {
        let defaults = try? SharedContainer.userDefaults()
        let raw = defaults?.string(forKey: FlowBridgeConstants.dictationLanguageKey)
        // Italian-first product: the default hint is Italian, not the phone
        // locale (an English-localized phone dictating Italian is the
        // primary user).
        return raw.flatMap(DictationLanguage.init(rawValue:)) ?? .italian
    }

    static func set(_ language: DictationLanguage) {
        let defaults = try? SharedContainer.userDefaults()
        defaults?.set(language.rawValue, forKey: FlowBridgeConstants.dictationLanguageKey)
    }
}

enum EngineFactory {
    static func makeCurrent() -> any TranscriptionEngine {
        make(EnginePreference.current)
    }

    static func make(_ preference: EnginePreference) -> any TranscriptionEngine {
        switch preference {
        case .whisper:
            return WhisperEngine()
        case .whisperPrecision:
            if WhisperModelLocator.precisionFolderIfInstalled() != nil {
                return WhisperEngine(variant: .precision)
            }
            return WhisperEngine()
        case .appleSpeech:
            return AppleSpeechEngine(locale: DictationLanguage.current.speechLocale ?? .current)
        case .cloudRealtime:
            return CloudScribeRealtimeEngine()
        }
    }
}
