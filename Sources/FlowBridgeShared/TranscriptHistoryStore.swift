import Foundation

/// Local dictation library: every finished transcript, searchable and
/// pinnable, capped at `FlowBridgeConstants.historyCapacity` records (pinned
/// records are never evicted). One JSON file in the App Group; at 200 short
/// texts this stays trivially small and needs no database.
public actor TranscriptHistoryStore {
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public let record: TranscriptRecord
        public var isPinned: Bool

        public var id: UUID { record.id }

        public init(record: TranscriptRecord, isPinned: Bool = false) {
            self.record = record
            self.isPinned = isPinned
        }
    }

    private let fileURL: URL
    private var cache: [Entry]?

    public init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = try SharedContainer.containerURL()
                .appendingPathComponent(FlowBridgeConstants.historyFileName)
        }
    }

    public func add(_ record: TranscriptRecord) throws {
        var entries = load()
        entries.insert(Entry(record: record), at: 0)

        let overflow = entries.count - FlowBridgeConstants.historyCapacity
        if overflow > 0 {
            // Evict oldest unpinned entries first.
            var removed = 0
            for index in stride(from: entries.count - 1, through: 0, by: -1) where removed < overflow {
                if !entries[index].isPinned {
                    entries.remove(at: index)
                    removed += 1
                }
            }
        }
        try save(entries)
    }

    public func all() -> [Entry] {
        load()
    }

    /// Case- and diacritic-insensitive full-text search.
    public func search(_ query: String) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load() }
        return load().filter {
            $0.record.text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    public func setPinned(_ pinned: Bool, id: UUID) throws {
        var entries = load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned = pinned
        try save(entries)
    }

    public func delete(id: UUID) throws {
        var entries = load()
        entries.removeAll { $0.id == id }
        try save(entries)
    }

    public func clear() throws {
        try save([])
    }

    private func load() -> [Entry] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder.decode([Entry].self, from: data) else {
            cache = []
            return []
        }
        cache = entries
        return entries
    }

    private func save(_ entries: [Entry]) throws {
        cache = entries
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }()
}
