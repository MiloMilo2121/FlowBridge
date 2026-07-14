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
    public private(set) var text: String
    /// Verbatim transcript before on-device polishing. Nil when the record
    /// was never polished (raw and text are the same).
    public let rawText: String?
    public let language: String
    public let createdAt: Date
    public let audioDuration: TimeInterval
    public let source: Source
    /// What this dictation became beyond text ("Calendar Event", "Reminder")
    /// — the voice → understanding → action trail in History. Nil for plain
    /// dictations; optional, so records saved before this field decode fine.
    public private(set) var actionTaken: String?

    public init(
        id: UUID = UUID(),
        text: String,
        rawText: String? = nil,
        language: String,
        createdAt: Date = Date(),
        audioDuration: TimeInterval,
        source: Source,
        actionTaken: String? = nil
    ) {
        self.id = id
        self.text = text
        self.rawText = rawText
        self.language = language
        self.createdAt = createdAt
        self.audioDuration = audioDuration
        self.source = source
        self.actionTaken = actionTaken
    }

    /// Same record with polished text applied and the verbatim original kept.
    public func polished(_ polishedText: String) -> TranscriptRecord {
        TranscriptRecord(
            id: id,
            text: polishedText,
            rawText: rawText ?? text,
            language: language,
            createdAt: createdAt,
            audioDuration: audioDuration,
            source: source,
            actionTaken: actionTaken
        )
    }

    /// Same record with the given field overridden — everything else,
    /// including `id`, carries over unchanged.
    public func withText(_ text: String) -> TranscriptRecord {
        var copy = self
        copy.text = text
        return copy
    }

    /// Same record with `actionTaken` stamped — the voice → action trail.
    public func withActionTaken(_ action: String) -> TranscriptRecord {
        var copy = self
        copy.actionTaken = action
        return copy
    }
}

