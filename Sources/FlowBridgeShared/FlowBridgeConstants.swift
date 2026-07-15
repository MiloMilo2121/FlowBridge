import Foundation

public enum FlowBridgeConstants {
    public static let appGroupIdentifier = "group.com.marcomilanello.flowbridge"
    public static let latestTranscriptKey = "latestTranscriptRecord"
    public static let pendingCommandKey = "pendingCommand"
    public static let queuedAudioPathKey = "queuedAudioPath"
    public static let modelFolderName = "WhisperSmall"
    public static let modelResourceSubdirectory = "WhisperModels"
    public static let maxRecordingSeconds: TimeInterval = 600
    public static let modelIdleTTLSeconds: TimeInterval = 180

    /// Darwin notification posted whenever a live transcript snapshot is
    /// written to the App Group. Payload-free; readers reload from the store.
    public static let liveTranscriptDidChangeDarwinName = "com.marcomilanello.flowbridge.liveTranscriptDidChange"

    /// Darwin notification posted whenever a pending command is written, so
    /// the app process reacts immediately even while backgrounded under an
    /// active audio session.
    public static let pendingCommandDidChangeDarwinName = "com.marcomilanello.flowbridge.pendingCommandDidChange"

    /// UserDefaults (App Group) key for the preferred transcription engine.
    /// Values: "whisper" (default, V1 behavior) or "appleSpeech".
    public static let preferredEngineKey = "preferredEngine"
    /// UserDefaults (App Group) key for the dictation language hint.
    /// Values: "auto", "it", "en". Pinning the language avoids per-chunk
    /// auto-detection — the main accuracy killer on short streaming windows.
    public static let dictationLanguageKey = "dictationLanguage"
    /// UserDefaults key: offer optional on-device refined variants after
    /// the verbatim transcript has already been delivered.
    public static let polishEnabledKey = "polishTranscripts"
    /// UserDefaults key: after stop, re-transcribe the full session audio in
    /// one pass (streaming quality is bounded by chunked decoding; the
    /// full-context pass is what offline WER benchmarks measure).
    /// Legacy bool key, superseded by `finalPassModeKey` (migration only).
    public static let finalPassEnabledKey = "finalPrecisionPass"
    /// UserDefaults key: final-pass provider — "off" | "localPrecision" |
    /// "cloudScribe".
    public static let finalPassModeKey = "finalPassMode"
    /// UserDefaults key: words the user dismissed from vocabulary
    /// suggestions (JSON array of lowercased strings).
    public static let vocabularyDismissedKey = "vocabularyDismissedSuggestions"
    /// Sessions longer than this skip the final pass to keep stop latency
    /// bounded.
    public static let finalPassMaxSeconds: TimeInterval = 180
    /// UserDefaults (App Group) key: label speakers ("Speaker 1/2/…") in the
    /// final transcript when more than one voice is detected.
    public static let speakersEnabledKey = "detectSpeakers"
    /// Labeled transcripts with more turns than this skip the polisher —
    /// per-turn polishing an hour of back-and-forth would take minutes.
    public static let speakerPolishMaxTurns = 8
    /// Folder reference (bundle) holding the diarization CoreML models,
    /// populated at build time by scripts/fetch-diarization-models.sh.
    public static let diarizationModelsSubdirectory = "DiarizationModels"
    /// UserDefaults key: onboarding was completed.
    public static let onboardingCompletedKey = "onboardingCompleted"

    /// How long the "ready" Live Activity stays in the Dynamic Island before
    /// dismissing itself.
    public static let liveActivityIdleDismissSeconds: TimeInterval = 6

    /// UserDefaults (App Group) key holding the user vocabulary (JSON).
    public static let vocabularyKey = "userVocabulary"
    /// File name of the transcript history JSON in the App Group container.
    public static let historyFileName = "TranscriptHistory.json"
    /// Maximum records kept in the local history.
    public static let historyCapacity = 200
    /// UserDefaults (App Group) key holding cumulative dictation stats (JSON).
    public static let statsKey = "dictationStats"
    /// UserDefaults (App Group) key holding per-day dictation stats (JSON
    /// array of day buckets) — feeds charts and the streak.
    public static let dailyStatsKey = "dictationDailyStats"
    /// Maximum daily buckets kept (~13 months of history).
    public static let dailyStatsCapacity = 400
    /// UserDefaults key: master switch for in-app haptics. CoreHaptics does
    /// not follow the system haptics toggle, so the app offers its own.
    public static let hapticsEnabledKey = "hapticsEnabled"
    /// UserDefaults key: haptic micro-transients on voice peaks while
    /// recording (off by default — an acquired taste).
    public static let hapticVoicePeaksEnabledKey = "hapticVoicePeaks"
    /// UserDefaults key: barely-perceptible tick when a streamed word lands.
    public static let hapticWordTickEnabledKey = "hapticWordTick"
    /// UserDefaults (App Group) key holding the latest tone hint from the
    /// keyboard (JSON).
    public static let toneHintKey = "toneHint"
    /// UserDefaults key: default tone when no fresh hint exists.
    public static let defaultToneKey = "defaultTone"
    /// Tone hints older than this are ignored.
    public static let toneHintMaxAgeSeconds: TimeInterval = 600
    /// UserDefaults key: apply spoken punctuation/newline commands.
    public static let voiceCommandsEnabledKey = "voiceCommandsEnabled"
    /// UserDefaults key: window (seconds) in which a new dictation is
    /// appended to the previous one. 0 disables session append.
    public static let sessionAppendWindowKey = "sessionAppendWindow"
    public static let sessionAppendWindowDefault: TimeInterval = 300
    /// Words-per-minute baselines used for the "time given back" stat:
    /// average mobile typing ~38 WPM vs speaking ~150 WPM.
    public static let typingWordsPerMinute: Double = 38
    /// Folder (in the app's Application Support) where an optional
    /// higher-accuracy Whisper model can be installed for the Precision
    /// engine. No runtime download: the folder is populated at build time or
    /// sideloaded explicitly by the user.
    public static let precisionModelFolderName = "PrecisionModel"

    /// Keyboard live updates are Darwin-notification driven. The legacy
    /// 250ms polling loop is kept behind this flag as a fallback; when the
    /// flag is off the keyboard still runs a slow safety refresh so a missed
    /// notification can never strand a stale transcript.
    public static let keyboardLegacyPollingEnabled = false
    public static let keyboardLegacyPollingInterval: TimeInterval = 0.25
    public static let keyboardSafetyRefreshInterval: TimeInterval = 2.0

    public static let safetyBufferDirectoryName = "SafetyBuffer"
    public static let safetyBufferSampleRate: Double = 16_000
    public static let safetyBufferFlushInterval: TimeInterval = 1.0
    /// Interrupted recordings shorter than this are discarded instead of
    /// recovered: below ~1s there is no usable speech.
    public static let safetyBufferMinimumRecoverySeconds: TimeInterval = 1.0
}

/// A model-role plan independent of WhisperKit, Core ML, and the UI. Keeping
/// this decision in the shared target makes the memory-safety invariant easy
/// to regression-test: an optional heavyweight model is never a live-stream
/// dependency, and it is only eligible for an offline pass after that exact
/// artifact has passed physical-device validation.
public enum LocalWhisperModelChoice: Equatable, Sendable {
    case bundled
    case precision
}

public enum LocalWhisperRuntimePlan {
    public static func liveModel(precisionRequested: Bool) -> LocalWhisperModelChoice {
        // The bundled model owns the microphone path even in Enhanced mode.
        // Loading a 626 MB compressed model for streaming can create multi-GB
        // inference buffers and makes a recording vulnerable to Jetsam.
        .bundled
    }

    public static func finalModel(
        precisionInstalled: Bool,
        precisionValidated: Bool
    ) -> LocalWhisperModelChoice {
        precisionInstalled && precisionValidated ? .precision : .bundled
    }

    public static func shouldRunLocalFinalPass(
        configured: Bool,
        precisionRequested: Bool,
        speakerDetection: Bool
    ) -> Bool {
        configured || precisionRequested || speakerDetection
    }
}
