import FlowBridgeShared
import Foundation
import XCTest

final class TranscriptHistoryStoreTests: XCTestCase {
    func testAddAndSearch() async throws {
        let store = try makeStore()
        try await store.add(record(text: "Nota sul contratto di Milano"))
        try await store.add(record(text: "Lista della spesa"))

        let all = await store.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.record.text, "Lista della spesa")

        let hits = await store.search("contratto")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.record.text, "Nota sul contratto di Milano")

        let caseInsensitive = await store.search("MILANO")
        XCTAssertEqual(caseInsensitive.count, 1)
    }

    func testPinAndDelete() async throws {
        let store = try makeStore()
        let first = record(text: "da tenere")
        try await store.add(first)
        try await store.add(record(text: "da cancellare"))

        try await store.setPinned(true, id: first.id)
        var all = await store.all()
        XCTAssertTrue(all.first(where: { $0.id == first.id })?.isPinned == true)

        if let disposable = all.first(where: { $0.record.text == "da cancellare" }) {
            try await store.delete(id: disposable.id)
        }
        all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.record.text, "da tenere")
    }

    func testCapacityEvictsOldestUnpinned() async throws {
        let store = try makeStore()
        let pinned = record(text: "pinned-0")
        try await store.add(pinned)
        try await store.setPinned(true, id: pinned.id)

        for index in 1...(FlowBridgeConstants.historyCapacity + 5) {
            try await store.add(record(text: "entry-\(index)"))
        }

        let all = await store.all()
        XCTAssertEqual(all.count, FlowBridgeConstants.historyCapacity)
        XCTAssertTrue(all.contains { $0.record.text == "pinned-0" })
        XCTAssertFalse(all.contains { $0.record.text == "entry-1" })
    }

    private func makeStore() throws -> TranscriptHistoryStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
        return try TranscriptHistoryStore(fileURL: url)
    }

    private func record(text: String) -> TranscriptRecord {
        TranscriptRecord(text: text, language: "it", audioDuration: 1, source: .microphone)
    }
}
