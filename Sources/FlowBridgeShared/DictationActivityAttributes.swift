import Foundation

// ActivityKit exists on macOS but its types are iOS-only, so the module
// check alone is not enough (the SwiftPM verification build runs on macOS).
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Shared Live Activity contract between the app (which starts and updates
/// the activity) and the widget extension (which renders it in the Dynamic
/// Island and on the Lock Screen).
public struct DictationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum Phase: String, Codable, Hashable {
            case recording
            case transcribing
            case ready
            case failed
        }

        public static let maxLevelBars = 24
        /// Flat baseline so the island never renders an empty waveform.
        public static let restingLevels = [UInt8](repeating: 4, count: maxLevelBars)

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

        public init(
            phase: Phase,
            transcriptPreview: String,
            startedAt: Date,
            levels: [UInt8] = [],
            wordCount: Int? = nil,
            recordedSeconds: Int? = nil,
            capWarning: Bool = false
        ) {
            self.phase = phase
            self.transcriptPreview = String(transcriptPreview.suffix(220))
            self.startedAt = startedAt
            self.levels = Array(levels.suffix(Self.maxLevelBars))
            self.wordCount = wordCount
            self.recordedSeconds = recordedSeconds
            self.capWarning = capWarning
        }
    }

    public var sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}
#endif
