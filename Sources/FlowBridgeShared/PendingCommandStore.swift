import Foundation

public enum FlowBridgeCommand: String, Codable, Sendable {
    case toggleRecording
    case stopRecording
    case transcribeQueuedAudio
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
        let data = try FlowBridgeJSON.encoder().encode(PendingCommand(command: command))
        defaults.set(data, forKey: FlowBridgeConstants.pendingCommandKey)
        DarwinNotifier.post(FlowBridgeConstants.pendingCommandDidChangeDarwinName)
    }

    public func consume() -> PendingCommand? {
        guard let data = defaults.data(forKey: FlowBridgeConstants.pendingCommandKey) else {
            return nil
        }
        defaults.removeObject(forKey: FlowBridgeConstants.pendingCommandKey)
        return try? FlowBridgeJSON.decoder().decode(PendingCommand.self, from: data)
    }
}
