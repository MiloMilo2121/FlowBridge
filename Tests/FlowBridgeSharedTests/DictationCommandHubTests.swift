import FlowBridgeShared
import Foundation
import XCTest

/// The hub is what an App Intent calls. `requestStart` reporting success
/// without a handler is the bug: the user would see "dictation started"
/// while nothing is recording.
///
/// The hub is `@MainActor`; the tests are isolated one by one rather than
/// the whole class, so the XCTest overrides keep XCTest's own isolation.
final class DictationCommandHubTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            let hub = DictationCommandHub.shared
            hub.startHandler = nil
            hub.stopHandler = nil
            hub.toggleHandler = nil
        }
    }

    @MainActor
    func testRequestStartThrowsWithoutAHandler() async {
        DictationCommandHub.shared.startHandler = nil

        do {
            try await DictationCommandHub.shared.requestStart()
            XCTFail("An unhandled start must not report success")
        } catch let error as FlowBridgeError {
            XCTAssertEqual(error, .noDictationHandler)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testRequestStartInvokesTheHandler() async throws {
        let hub = DictationCommandHub.shared
        let recorder = Recorder()
        hub.startHandler = { await recorder.recordStart() }

        try await hub.requestStart()

        let starts = await recorder.starts
        XCTAssertEqual(starts, 1)
    }

    @MainActor
    func testRequestStartPropagatesHandlerFailure() async {
        let hub = DictationCommandHub.shared
        hub.startHandler = { throw FlowBridgeError.microphonePermissionDenied }

        do {
            try await hub.requestStart()
            XCTFail("A failing start must not report success")
        } catch let error as FlowBridgeError {
            XCTAssertEqual(error, .microphonePermissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor Recorder {
    private(set) var starts = 0
    func recordStart() { starts += 1 }
}
