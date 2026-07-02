import Foundation

#if canImport(ActivityKit)
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

        public var phase: Phase
        /// Last words of the live transcript, kept short: the combined
        /// static + dynamic Live Activity payload must stay under 4KB.
        public var transcriptPreview: String
        public var startedAt: Date

        public init(phase: Phase, transcriptPreview: String, startedAt: Date) {
            self.phase = phase
            self.transcriptPreview = String(transcriptPreview.suffix(220))
            self.startedAt = startedAt
        }
    }

    public var sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}
#endif
