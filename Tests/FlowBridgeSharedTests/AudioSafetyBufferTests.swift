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

    func testPendingRecordingsIgnoresNonWavFiles() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("not audio".utf8).write(to: directory.appendingPathComponent("note.txt"))
        XCTAssertTrue(AudioSafetyBuffer.pendingRecordings(in: directory).isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSafetyBufferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
