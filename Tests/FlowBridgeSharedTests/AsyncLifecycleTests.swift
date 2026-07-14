import FlowBridgeShared
import XCTest

final class AsyncLifecycleTests: XCTestCase {
    func testOperationGateRejectsReentryUntilLeave() {
        var gate = AsyncOperationGate()

        XCTAssertTrue(gate.enterIfAvailable())
        XCTAssertTrue(gate.isEntered)
        XCTAssertFalse(gate.enterIfAvailable())

        gate.leave()

        XCTAssertFalse(gate.isEntered)
        XCTAssertTrue(gate.enterIfAvailable())
    }

    func testTaskQuiescerWaitsForCancelledTaskCleanup() async {
        let probe = CleanupProbe()
        let task = Task {
            await probe.markStarted()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                // Simulates the cleanup WhisperKit performs after observing
                // cancellation, before the microphone is safe to reuse.
                await probe.markFinished()
            }
        }
        var didStart = false
        for _ in 0..<100 {
            didStart = await probe.didStart
            if didStart { break }
            await Task.yield()
        }
        XCTAssertTrue(didStart)

        await TaskQuiescer.cancelAndWait(task)

        let didFinish = await probe.didFinish
        XCTAssertTrue(didFinish)
    }
}

private actor CleanupProbe {
    private(set) var didStart = false
    private(set) var didFinish = false

    func markStarted() {
        didStart = true
    }

    func markFinished() {
        didFinish = true
    }
}
