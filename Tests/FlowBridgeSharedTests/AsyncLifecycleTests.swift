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

    func testTaskDeadlineReturnsFallbackWithoutWaitingForSlowWork() async {
        let slow = Task<String, Never> {
            try? await Task.sleep(for: .seconds(2))
            return "late"
        }
        let started = ContinuousClock.now

        let outcome = await TaskDeadline.value(
            from: slow,
            fallback: "verbatim",
            after: .milliseconds(25)
        )

        XCTAssertTrue(outcome.timedOut)
        XCTAssertEqual(outcome.value, "verbatim")
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(500))
    }

    func testInterruptedRecoveryGuardPersistsAndClearsAttempt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InterruptedRecoveryGuardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = directory.appendingPathComponent("session.wav")
        try Data("RIFF".utf8).write(to: recording)

        XCTAssertFalse(InterruptedRecoveryGuard.hasAttempted(recording))
        try InterruptedRecoveryGuard.markAttempted(recording)
        XCTAssertTrue(InterruptedRecoveryGuard.hasAttempted(recording))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: InterruptedRecoveryGuard.markerURL(for: recording).path
        ))

        InterruptedRecoveryGuard.clear(recording)
        XCTAssertFalse(InterruptedRecoveryGuard.hasAttempted(recording))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.path))
    }

    func testPrecisionRequestNeverLoadsHeavyModelForLiveStreaming() {
        XCTAssertEqual(
            LocalWhisperRuntimePlan.liveModel(precisionRequested: true),
            .bundled
        )
    }

    func testHeavyFinalModelRequiresInstalledAndValidatedArtifact() {
        XCTAssertEqual(
            LocalWhisperRuntimePlan.finalModel(
                precisionInstalled: true,
                precisionValidated: false
            ),
            .bundled
        )
        XCTAssertEqual(
            LocalWhisperRuntimePlan.finalModel(
                precisionInstalled: true,
                precisionValidated: true
            ),
            .precision
        )
    }

    func testEnhancedModeForcesSafeLocalFinalPass() {
        XCTAssertTrue(
            LocalWhisperRuntimePlan.shouldRunLocalFinalPass(
                configured: false,
                precisionRequested: true,
                speakerDetection: false
            )
        )
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
