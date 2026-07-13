import FlowBridgeShared
import Foundation
import XCTest

final class TranscriptStoreTests: XCTestCase {
    func testSavesAndLoadsLatestTranscript() async throws {
        // One UserDefaults instance per use: the store actor consumes its
        // instance (region-based isolation forbids reusing it afterwards);
        // both instances share the same suite on disk.
        let suite = "FlowBridgeTests.\(UUID().uuidString)"
        try XCTUnwrap(UserDefaults(suiteName: suite)).removePersistentDomain(forName: suite)
        let store = try TranscriptStore(defaults: XCTUnwrap(UserDefaults(suiteName: suite)))
        let record = TranscriptRecord(
            text: "Hello from FlowBridge.",
            language: "en",
            audioDuration: 2.5,
            source: .microphone
        )

        try await store.save(record)

        let loaded = await store.latest()
        XCTAssertEqual(loaded, record)
        let checkDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(TranscriptStore.latest(defaults: checkDefaults), record)
    }
}
