import FlowBridgeShared
import Foundation
import XCTest

/// `isError` is what stops the keyboard from diffing an error snapshot's
/// empty text into the host field and deleting the user's dictation.
final class LiveTranscriptSnapshotTests: XCTestCase {
    private let sessionID = UUID()

    func testErrorSnapshotIsFlagged() throws {
        let (store, defaults) = try makeStore()
        store.writeError(sessionID: sessionID, sequence: 7, message: "Network unavailable.")

        let snapshot = try XCTUnwrap(LiveTranscriptStore.latest(defaults: defaults))
        XCTAssertTrue(snapshot.isError)
        XCTAssertTrue(snapshot.text.isEmpty)
        XCTAssertEqual(snapshot.previewText, "Network unavailable.")
        XCTAssertFalse(snapshot.isRecording)
        XCTAssertTrue(snapshot.isFinal)
    }

    func testLiveAndFinalSnapshotsAreNotErrors() throws {
        let live = LiveTranscriptSnapshot(
            sessionID: sessionID,
            sequence: 1,
            text: "ciao",
            previewText: "cia",
            isRecording: true,
            isFinal: false
        )
        XCTAssertFalse(live.isError, "A recording in progress is never an error")

        let (store, defaults) = try makeStore()
        store.writeFinal(sessionID: sessionID, text: "Ciao.")
        let final = try XCTUnwrap(LiveTranscriptStore.latest(defaults: defaults))
        XCTAssertFalse(final.isError, "A delivered transcript is not an error")
    }

    func testEmptyFinalWithoutMessageIsNotAnError() throws {
        // The empty-transcript path: nothing to show, nothing to undo, so the
        // keyboard must not treat it as a message.
        let (store, defaults) = try makeStore()
        store.writeFinal(sessionID: sessionID, text: "")
        let snapshot = try XCTUnwrap(LiveTranscriptStore.latest(defaults: defaults))
        XCTAssertFalse(snapshot.isError)
    }

    func testErrorSnapshotRoundTripsThroughTheStore() throws {
        let (store, defaults) = try makeStore()
        store.writeError(sessionID: sessionID, sequence: 42, message: "Cloud upload failed.")
        let readBack = try XCTUnwrap(LiveTranscriptStore.latest(defaults: defaults))
        XCTAssertTrue(readBack.isError, "isError must survive encoding: it is derived, not stored")
        XCTAssertEqual(readBack.sequence, 42)
        XCTAssertEqual(readBack.previewText, "Cloud upload failed.")
    }

    func testErrorWithAnEmptyMessageIsStillAnError() throws {
        // An empty message would make the snapshot look like an empty final,
        // and the error would vanish from the keyboard.
        let (store, defaults) = try makeStore()
        store.writeError(sessionID: sessionID, sequence: 3, message: "  ")
        let snapshot = try XCTUnwrap(LiveTranscriptStore.latest(defaults: defaults))
        XCTAssertTrue(snapshot.isError)
        XCTAssertEqual(snapshot.previewText, LiveTranscriptStore.genericErrorMessage)
    }

    private func makeStore() throws -> (LiveTranscriptStore, UserDefaults) {
        let suite = "FlowBridgeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (try LiveTranscriptStore(defaults: defaults), defaults)
    }
}
