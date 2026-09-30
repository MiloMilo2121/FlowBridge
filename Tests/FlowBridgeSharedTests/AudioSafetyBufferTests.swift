import FlowBridgeShared
import Foundation
import XCTest

final class AudioSafetyBufferTests: XCTestCase {
    func testBeginAppendKeepsValidWavOnDisk() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory, sampleRate: 16_000)
        let sessionID = UUID()
        try await buffer.begin(sessionID: sessionID)
        try await buffer.append([0, 0.5, -0.5, 1.0])

        let url = directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension("wav")
        let data = try Data(contentsOf: url)

        XCTAssertEqual(data.count, 44 + 4 * 2)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")

        let dataSize = data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: dataSize), 8)

        let riffSize = data[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: riffSize), 36 + 8)

        let firstSample = data[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        XCTAssertEqual(Int16(littleEndian: firstSample), 0)

        await buffer.closeKeepingFile()
    }

    func testCompleteAndRemoveDeletesFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append([0.1, 0.2])
        await buffer.completeAndRemove()

        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    func testCloseKeepingFileLeavesPendingRecordingWithDuration() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sampleRate = 16_000.0
        let buffer = AudioSafetyBuffer(directory: directory, sampleRate: sampleRate)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append([Float](repeating: 0.25, count: 32_000))
        await buffer.closeKeepingFile()

        let pending = AudioSafetyBuffer.pendingRecordings(in: directory, sampleRate: sampleRate)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].duration, 2.0, accuracy: 0.001)

        AudioSafetyBuffer.remove(pending[0])
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    func testSamplesAreClampedToValidRange() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        let sessionID = UUID()
        try await buffer.begin(sessionID: sessionID)
        try await buffer.append([2.0, -2.0])
        await buffer.closeKeepingFile()

        let url = directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension("wav")
        let data = try Data(contentsOf: url)

        let high = data[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        let low = data[46..<48].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        XCTAssertEqual(Int16(littleEndian: high), Int16.max)
        XCTAssertEqual(Int16(littleEndian: low), -Int16.max)
    }

    // MARK: - Recovery attempts (crash-safety: audio is never destroyed)

    func testFailedRecoveryKeepsTheFileAndCountsTheAttempt() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sampleRate = 16_000.0
        let buffer = AudioSafetyBuffer(directory: directory, sampleRate: sampleRate)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append([Float](repeating: 0.25, count: 16_000))
        await buffer.closeKeepingFile()

        let fresh = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        XCTAssertEqual(fresh.recoveryAttempt, 0, "A never-tried recording must report no attempts")

        // The attempt is counted before transcribing: renamed, not deleted.
        let marked = try XCTUnwrap(AudioSafetyBuffer.recordRecoveryAttempt(fresh))
        XCTAssertEqual(marked.recoveryAttempt, 1)

        let afterFailure = AudioSafetyBuffer.pendingRecordings(in: directory, sampleRate: sampleRate)
        XCTAssertEqual(afterFailure.count, 1, "A failed recovery must not lose the audio")
        XCTAssertEqual(afterFailure[0].recoveryAttempt, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: afterFailure[0].url.path),
            "The WAV must survive a failed recovery"
        )
        // The rename must not disturb what makes the file recoverable.
        XCTAssertEqual(afterFailure[0].duration, 1.0, accuracy: 0.001)
    }

    func testRepeatedFailuresAdvanceTheAttemptCounter() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append([Float](repeating: 0.25, count: 16_000))
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
        try await buffer.append([Float](repeating: 0.25, count: 16_000))
        await buffer.closeKeepingFile()

        let pending = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)
        // What the coordinator does once the transcript is safely stored.
        AudioSafetyBuffer.remove(pending)
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    func testMarkingAMissingFileIsBestEffort() {
        let missing = AudioSafetyBuffer.PendingRecording(
            url: URL(fileURLWithPath: "/tmp/flowbridge-does-not-exist-\(UUID().uuidString).wav"),
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
        let wav = try XCTUnwrap(AudioSafetyBuffer.pendingRecordings(in: directory).first)

        let stale = AudioSafetyBuffer.uploadBodyURL(for: wav.url)
        let fresh = AudioSafetyBuffer.uploadBodyURL(for: wav.url)
        let unrelated = directory.appendingPathComponent("notes.tmp")
        for url in [stale, fresh, unrelated] {
            try Data("body".utf8).write(to: url)
        }
        let twoHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: stale.path)
        try FileManager.default.setAttributes([.modificationDate: twoHoursAgo], ofItemAtPath: unrelated.path)

        XCTAssertTrue(
            AudioSafetyBuffer.pendingRecordings(in: directory).allSatisfy { $0.url.pathExtension == "wav" },
            "Upload bodies must never look like a dictation to recover"
        )
        XCTAssertEqual(AudioSafetyBuffer.removeStaleUploadBodies(in: directory), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path), "The orphan goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "An upload in flight stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path), "Only upload bodies are touched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wav.url.path), "The WAV is never touched")
    }

    func testPendingRecordingsIgnoresNonWavFiles() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("not audio".utf8).write(to: directory.appendingPathComponent("note.txt"))
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    private func writeOneSecondRecording(in directory: URL) async throws {
        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: UUID())
        try await buffer.append([Float](repeating: 0.25, count: 16_000))
        await buffer.closeKeepingFile()
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSafetyBufferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
