import Foundation

public struct TranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case microphone
        case sharedAudio
        /// Rebuilt from the crash-safe audio buffer after an interrupted
        /// live session (see `AudioSafetyBuffer`).
        case recovered
    }

    public let id: UUID
    public let text: String
    public let language: String
    public let createdAt: Date
    public let audioDuration: TimeInterval
    public let source: Source

    public init(
        id: UUID = UUID(),
        text: String,
        language: String,
        createdAt: Date = Date(),
        audioDuration: TimeInterval,
        source: Source
    ) {
        self.id = id
        self.text = text
        self.language = language
        self.createdAt = createdAt
        self.audioDuration = audioDuration
        self.source = source
    }
}

