import FlowBridgeShared
import Foundation

enum EnginePreference: String {
    /// WhisperKit, the V1 default. Stays the default until the Apple engine
    /// wins on our own benchmark set (`BenchmarkHarness`).
    case whisper
    /// iOS 26 SpeechAnalyzer/SpeechTranscriber (system model, opt-in).
    case appleSpeech

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
        case .appleSpeech:
            return AppleSpeechEngine()
        }
    }
}
