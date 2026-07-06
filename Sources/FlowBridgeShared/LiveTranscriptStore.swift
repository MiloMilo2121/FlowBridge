import Foundation

public struct LiveTranscriptSnapshot: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let sequence: Int
    public let text: String
    public let previewText: String
    public let isRecording: Bool
    public let isFinal: Bool
    public let updatedAt: Date

    public init(
        sessionID: UUID,
        sequence: Int,
        text: String,
        previewText: String,
        isRecording: Bool,
        isFinal: Bool,
        updatedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.text = text
        self.previewText = previewText
        self.isRecording = isRecording
        self.isFinal = isFinal
        self.updatedAt = updatedAt
    }
}

public final class LiveTranscriptStore: @unchecked Sendable {
    public static let key = "liveTranscriptSnapshot"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
    }

    public func write(_ snapshot: LiveTranscriptSnapshot) throws {
        let data = try FlowBridgeJSON.encoder().encode(snapshot)
        defaults.set(data, forKey: Self.key)
        DarwinNotifier.post(FlowBridgeConstants.liveTranscriptDidChangeDarwinName)
    }

    /// Terminal snapshot for a session (max sequence so no stale update can
    /// supersede it). Best-effort: delivery of the transcript itself never
    /// depends on this write.
    public func writeFinal(sessionID: UUID, text: String) {
        try? write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: Int.max,
                text: text,
                previewText: "",
                isRecording: false,
                isFinal: true
            )
        )
    }

    /// Terminal error snapshot: the message rides in the preview so the
    /// keyboard can show it without inserting anything.
    public func writeError(sessionID: UUID, sequence: Int, message: String) {
        try? write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: sequence,
                text: "",
                previewText: message,
                isRecording: false,
                isFinal: true
            )
        )
    }

    public func latest() -> LiveTranscriptSnapshot? {
        Self.latest(defaults: defaults)
    }

    public static func latest(defaults: UserDefaults? = nil) -> LiveTranscriptSnapshot? {
        let resolvedDefaults: UserDefaults
        if let defaults {
            resolvedDefaults = defaults
        } else if let appGroupDefaults = try? SharedContainer.userDefaults() {
            resolvedDefaults = appGroupDefaults
        } else {
            return nil
        }

        guard let data = resolvedDefaults.data(forKey: Self.key) else {
            return nil
        }

        return try? FlowBridgeJSON.decoder().decode(LiveTranscriptSnapshot.self, from: data)
    }
}

public final class LiveSequenceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    public init() {}

    public func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
