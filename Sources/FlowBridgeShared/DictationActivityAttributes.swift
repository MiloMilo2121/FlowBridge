import Foundation

// `canImport(ActivityKit)` e' VERO anche su macOS: il modulo c'e', ma
// `ActivityAttributes` e' dichiarato non disponibile. La guardia controllava
// quindi la cosa sbagliata, e su macOS il target condiviso non compilava.
#if canImport(ActivityKit) && !os(macOS)
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

        public var phase: Phase
        /// Last words of the live transcript, kept short: the combined
        /// static + dynamic Live Activity payload must stay under 4KB.
        public var transcriptPreview: String
        public var startedAt: Date
        /// Quantized microphone energy. Optional for activities restored from
        /// a build that predates the meter.
        public var level: UInt8?
        public var finishedAt: Date?
        public var isCloud: Bool?

        public init(phase: Phase, transcriptPreview: String, startedAt: Date,
                    level: UInt8 = 0, finishedAt: Date? = nil, isCloud: Bool = false) {
            self.phase = phase
            self.transcriptPreview = String(transcriptPreview.suffix(220))
            self.startedAt = startedAt
            self.level = level
            self.finishedAt = finishedAt
            self.isCloud = isCloud
        }
    }

    public var sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}
#endif
