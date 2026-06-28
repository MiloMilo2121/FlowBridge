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
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        self.decoder = decoder
    }

    public func write(_ snapshot: LiveTranscriptSnapshot) throws {
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: Self.key)
    }

    public func latest() -> LiveTranscriptSnapshot? {
        Self.latest(defaults: defaults)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
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

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try? decoder.decode(LiveTranscriptSnapshot.self, from: data)
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

