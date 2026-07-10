import FlowBridgeShared
import Foundation
import XCTest

final class PendingCommandStoreTests: XCTestCase {
    func testConsumesCommandOnce() throws {
        let defaults = try makeDefaults()
        let store = try PendingCommandStore(defaults: defaults)

        try store.write(.toggleRecording)

        XCTAssertEqual(store.consume()?.command, .toggleRecording)
        XCTAssertNil(store.consume())
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "FlowBridgeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
