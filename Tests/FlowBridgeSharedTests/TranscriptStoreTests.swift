import FlowBridgeShared
import Foundation
import XCTest

final class TranscriptStoreTests: XCTestCase {
    func testSavesAndLoadsLatestTranscript() async throws {
        let defaults = try makeDefaults()
        let store = try TranscriptStore(defaults: defaults)
        let record = TranscriptRecord(
            text: "Hello from FlowBridge.",
            language: "en",
            audioDuration: 2.5,
            source: .microphone
        )

        try store.save(record)

        let loaded = store.latest()
        XCTAssertEqual(loaded, record)
        XCTAssertEqual(TranscriptStore.latest(defaults: defaults), record)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "FlowBridgeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
