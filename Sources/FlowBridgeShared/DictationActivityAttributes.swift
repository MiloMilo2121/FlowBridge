import Foundation

// ActivityKit exists on macOS but its types are iOS-only, so the module
// check alone is not enough (the SwiftPM verification build runs on macOS).
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Shared Live Activity contract between the app (which starts and updates
/// the activity) and the widget extension (which renders it in the Dynamic
/// Island and on the Lock Screen).
public struct DictationActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case recording
            case transcribing
            case ready
            case failed
        }

        public static let maxLevelBars = 24
        /// Flat baseline so the island never renders an empty waveform.
        public static let restingLevels = [UInt8](repeating: 4, count: maxLevelBars)

        /// Where the words are being made — privacy honesty rendered where
        /// the user is looking.
        public enum EngineBadge: String, Codable, Hashable, Sendable {
            case local
            case cloud
        }

        public var phase: Phase
        /// Last words of the live transcript, kept short: the combined
        /// static + dynamic Live Activity payload must stay under 4KB.
        public var transcriptPreview: String
        public var startedAt: Date
        /// Recent mic levels, oldest→newest, quantized 0…100. Capped at
        /// `maxLevelBars` entries (~100B encoded) — the waveform the island
        /// renders is real audio, not decoration.
        public var levels: [UInt8]
        /// Words in the delivered transcript; set only for `.ready`.
        public var wordCount: Int?
        /// Whole seconds of recorded audio; set from `.transcribing` on.
        public var recordedSeconds: Int?
        /// True inside the last minute before the recording cap: the island
        /// timer flips to an amber countdown.
        public var capWarning: Bool
        /// Local vs cloud — during recording: the live engine; during
        /// transcribing/refining: the final-pass provider.
        public var engineBadge: EngineBadge?
        /// The final pass is running (second micro-stage of transcribing).
        public var refining: Bool
        /// Ready-window: tone-variant buttons are live.
        public var variantsAvailable: Bool
        /// Confirmation after a variant tap ("Formal copied ✓").
        public var toneNote: String?
        /// Set while paused: freezes the island timer via
        /// `Text(timerInterval:pauseTime:)`.
        public var pausedAt: Date?

        public init(
            phase: Phase,
            transcriptPreview: String,
            startedAt: Date,
            levels: [UInt8] = [],
            wordCount: Int? = nil,
            recordedSeconds: Int? = nil,
            capWarning: Bool = false,
            engineBadge: EngineBadge? = nil,
            refining: Bool = false,
            variantsAvailable: Bool = false,
            toneNote: String? = nil,
            pausedAt: Date? = nil
        ) {
            self.phase = phase
            self.transcriptPreview = String(transcriptPreview.suffix(220))
            self.startedAt = startedAt
            self.levels = Array(levels.suffix(Self.maxLevelBars))
            self.wordCount = wordCount
            self.recordedSeconds = recordedSeconds
            self.capWarning = capWarning
            self.engineBadge = engineBadge
            self.refining = refining
            self.variantsAvailable = variantsAvailable
            self.toneNote = toneNote
            self.pausedAt = pausedAt
        }
    }

    public var sessionID: UUID
    /// Static per session, zero bytes per update ("it"/"en", nil = auto).
    public var language: String?

    public init(sessionID: UUID, language: String? = nil) {
        self.sessionID = sessionID
        self.language = language
    }
}
#endif
