import FlowBridgeShared
import Foundation
import XCTest

final class AudioSafetyBufferTests: XCTestCase {
    func testAppendWritesFramesToTheSessionFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        let sessionID = UUID()
        try await buffer.begin(sessionID: sessionID)
        try await buffer.append(Data([1, 2, 3]))
        try await buffer.append(Data([4, 5]))
        await buffer.closeKeepingFile()

        let url = AudioSafetyBuffer.fileURL(for: sessionID, in: directory)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3, 4, 5]))
    }

    func testCompleteAndRemoveDeletesFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append(Data([1, 2]))
        await buffer.completeAndRemove()

        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    func testCloseKeepingFileLeavesPendingRecordingWithDuration() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append(Data(count: 16_000))
        await buffer.closeKeepingFile()

        let pending = AudioSafetyBuffer.pendingRecordings(in: directory)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].duration, 2.0, accuracy: 0.001)

        AudioSafetyBuffer.remove(pending[0])
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    // MARK: - Recovery attempts (crash-safety: audio is never destroyed)

    func testFailedRecoveryKeepsTheFileAndCountsTheAttempt() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append(Data(count: 8_000))
        await buffer.closeKeepingFile()

        let fresh = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        XCTAssertEqual(fresh.recoveryAttempt, 0, "A never-tried recording must report no attempts")

        // The attempt is counted before transcribing: renamed, not deleted.
        let marked = try XCTUnwrap(AudioSafetyBuffer.recordRecoveryAttempt(fresh))
        XCTAssertEqual(marked.recoveryAttempt, 1)

        let afterFailure = AudioSafetyBuffer.pendingRecordings(in: directory)
        XCTAssertEqual(afterFailure.count, 1, "A failed recovery must not lose the audio")
        XCTAssertEqual(afterFailure[0].recoveryAttempt, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: afterFailure[0].url.path),
            "The recording must survive a failed recovery"
        )
        // The rename must not disturb what makes the file recoverable.
        XCTAssertEqual(afterFailure[0].duration, 1.0, accuracy: 0.001)
    }

    func testRepeatedFailuresAdvanceTheAttemptCounter() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append(Data(count: 8_000))
        await buffer.closeKeepingFile()

        var pending = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        for expected in 1...FlowBridgeConstants.safetyBufferMaxRecoveryAttempts {
            pending = try XCTUnwrap(AudioSafetyBuffer.recordRecoveryAttempt(pending))
            XCTAssertEqual(pending.recoveryAttempt, expected)
            let found = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
            XCTAssertEqual(found.recoveryAttempt, expected, "The attempt count must survive the rename")
        }

        // Past the cap the file is still there — the loop stops, the audio stays.
        let exhausted = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        XCTAssertGreaterThanOrEqual(
            exhausted.recoveryAttempt,
            FlowBridgeConstants.safetyBufferMaxRecoveryAttempts
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: exhausted.url.path))
    }

    func testSuccessfulRecoveryRemovesTheFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append(Data(count: 8_000))
        await buffer.closeKeepingFile()

        let pending = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        // What the coordinator does once the transcript is safely stored.
        AudioSafetyBuffer.remove(pending)
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    func testMarkingAMissingFileIsBestEffort() {
        let missing = AudioSafetyBuffer.PendingRecording(
            url: URL(fileURLWithPath: "/tmp/flowbridge-does-not-exist-\(UUID().uuidString).aac"),
            duration: 1
        )
        XCTAssertNil(
            AudioSafetyBuffer.recordRecoveryAttempt(missing),
            "Renaming a file that is not there must fail quietly, not throw"
        )
    }

    func testWithdrawnAttemptGivesTheCountBack() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await writeOneSecondRecording(in: directory)

        let fresh = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        let attempted = try XCTUnwrap(AudioSafetyBuffer.recordRecoveryAttempt(fresh))
        // A transient failure (offline cloud) must not count against the file.
        let withdrawn = try XCTUnwrap(AudioSafetyBuffer.withdrawRecoveryAttempt(attempted))
        XCTAssertEqual(withdrawn.recoveryAttempt, 0)
        XCTAssertEqual(withdrawn.url.lastPathComponent, fresh.url.lastPathComponent, "Back to the plain name")
        XCTAssertEqual(AudioSafetyBuffer.pendingRecordings(in: directory).first?.recoveryAttempt, 0)
    }

    func testExhaustedRecordingsAreListedAndCanBeReset() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await writeOneSecondRecording(in: directory)
        try await writeOneSecondRecording(in: directory)

        var pending = AudioSafetyBuffer.pendingRecordings(in: directory)
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(AudioSafetyBuffer.exhaustedRecordings(in: directory).isEmpty)
        XCTAssertNotNil(pending[0].recordedAt, "The recording date must come from the file")

        // Exhaust only the first one.
        var first = pending[0]
        while !first.isExhausted {
            first = try XCTUnwrap(AudioSafetyBuffer.recordRecoveryAttempt(first))
        }
        let exhausted = AudioSafetyBuffer.exhaustedRecordings(in: directory)
        XCTAssertEqual(exhausted.map(\.url), [first.url])
        // Creation-date granularity and rename semantics differ per
        // filesystem (Linux ext4/overlayfs vs APFS): closeness, not identity.
        let exhaustedDate = try XCTUnwrap(exhausted[0].recordedAt)
        let originalDate = try XCTUnwrap(pending[0].recordedAt)
        XCTAssertEqual(exhaustedDate.timeIntervalSince(originalDate), 0, accuracy: 5, "Renames keep the recording date")

        // A user-initiated retry starts from scratch.
        let reset = try XCTUnwrap(AudioSafetyBuffer.resetRecoveryAttempts(exhausted[0]))
        XCTAssertEqual(reset.recoveryAttempt, 0)
        XCTAssertTrue(AudioSafetyBuffer.exhaustedRecordings(in: directory).isEmpty)
        pending = AudioSafetyBuffer.pendingRecordings(in: directory)
        XCTAssertEqual(pending.count, 2, "Nothing is ever lost along the way")
    }

    func testStaleUploadBodiesAreSweptAndNothingElse() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await writeOneSecondRecording(in: directory)
        let recording = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)

        let stale = AudioSafetyBuffer.uploadBodyURL(for: recording.url)
        let fresh = AudioSafetyBuffer.uploadBodyURL(for: recording.url)
        let unrelated = directory.appendingPathComponent("notes.tmp")
        for url in [stale, fresh, unrelated] {
            try Data("body".utf8).write(to: url)
        }
        let twoHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: stale.path)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: unrelated.path)

        XCTAssertTrue(
            AudioSafetyBuffer.pendingRecordings(in: directory).allSatisfy { $0.url.pathExtension == "aac" },
            "Upload bodies must never look like a dictation to recover"
        )
        XCTAssertEqual(AudioSafetyBuffer.removeStaleUploadBodies(in: directory), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "The orphan goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "An upload in flight stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path), "Only upload bodies are touched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path), "The recording is never touched")
    }

    func testPendingRecordingsIgnoresOtherFiles() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("not audio".utf8).write(to: directory.appendingPathComponent("note.txt"))
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    private func writeOneSecondRecording(in directory: URL) async throws {
        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append(Data(count: 8_000))
        await buffer.closeKeepingFile()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSafetyBufferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
