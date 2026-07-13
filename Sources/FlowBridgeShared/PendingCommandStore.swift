import Foundation

public enum FlowBridgeCommand: String, Codable, Sendable {
    case toggleRecording
    case stopRecording
    case transcribeQueuedAudio
    case pauseRecording
    case resumeRecording
}

public struct PendingCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let command: FlowBridgeCommand
    public let createdAt: Date

    public init(id: UUID = UUID(), command: FlowBridgeCommand, createdAt: Date = Date()) {
        self.id = id
        self.command = command
        self.createdAt = createdAt
    }
}

public final class PendingCommandStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
    }

    public func write(_ command: FlowBridgeCommand) throws {
        let data = try JSONEncoder.flowBridge.encode(PendingCommand(command: command))
        defaults.set(data, forKey: FlowBridgeConstants.pendingCommandKey)
        DarwinNotifier.post(FlowBridgeConstants.pendingCommandDidChangeDarwinName)
    }

    public func consume() -> PendingCommand? {
        guard let data = defaults.data(forKey: FlowBridgeConstants.pendingCommandKey) else {
            return nil
        }
        defaults.removeObject(forKey: FlowBridgeConstants.pendingCommandKey)
        return try? JSONDecoder.flowBridge.decode(PendingCommand.self, from: data)
    }
}

private extension JSONEncoder {
    static var flowBridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }
}

private extension JSONDecoder {
    static var flowBridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
