import Foundation

/// Crash-safe audio buffer for live dictation.
///
/// While a live session runs, incoming samples are appended to a WAV file in
/// the App Group container. The file stays a valid 16-bit PCM WAV after every
/// append (the header sizes are patched in place), so a session interrupted
/// by a crash or a system kill leaves behind a playable, transcribable file.
/// Completing a session removes the file; anything found on the next launch
/// is an interrupted dictation to recover.
///
/// Writes are best-effort by design: a safety-buffer failure must never break
/// the live dictation it protects.
public actor AudioSafetyBuffer {
    public struct PendingRecording: Equatable, Sendable {
        public let url: URL
        public let duration: TimeInterval

        public init(url: URL, duration: TimeInterval) {
            self.url = url
            self.duration = duration
        }
    }

    private static let headerByteCount = 44
    private static let bytesPerSample = 2

    private let directory: URL
    private let sampleRate: Double
    private var fileHandle: FileHandle?
    private var fileURL: URL?
    private var sampleCount = 0

    public init(directory: URL, sampleRate: Double = FlowBridgeConstants.safetyBufferSampleRate) {
        self.directory = directory
        self.sampleRate = sampleRate
    }

    public static func defaultDirectory() throws -> URL {
        let url = try SharedContainer.containerURL()
            .appendingPathComponent(FlowBridgeConstants.safetyBufferDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func begin(sessionID: UUID) throws {
        closeKeepingFile()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(sessionID.uuidString).appendingPathExtension("wav")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)

        let handle = try FileHandle(forWritingTo: url)
        sampleCount = 0
        try handle.write(contentsOf: Self.header(sampleCount: 0, sampleRate: sampleRate))

        fileHandle = handle
        fileURL = url
    }

    public func append(_ samples: [Float]) throws {
        guard let fileHandle else { return }
        guard !samples.isEmpty else { return }

        var data = Data(capacity: samples.count * Self.bytesPerSample)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16((clamped * Float(Int16.max)).rounded())
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)
        sampleCount += samples.count
        try patchHeaderSizes(on: fileHandle)
    }

    /// Ends the session and deletes the file: the dictation finished normally
    /// and there is nothing left to recover.
    public func completeAndRemove() {
        let url = fileURL
        closeKeepingFile()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Closes the file handle but leaves the WAV on disk. Used when the
    /// session ends without a transcript (unload under pressure, crash paths)
    /// so the next launch can recover the audio.
    public func closeKeepingFile() {
        try? fileHandle?.close()
        fileHandle = nil
        fileURL = nil
        sampleCount = 0
    }

    public static func pendingRecordings(
        in directory: URL,
        sampleRate fallbackSampleRate: Double = FlowBridgeConstants.safetyBufferSampleRate
    ) -> [PendingRecording] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "wav" }
            .compactMap { url in
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                    return nil
                }
                let sampleRate = headerSampleRate(of: url) ?? fallbackSampleRate
                let payloadBytes = max(0, size - headerByteCount)
                let duration = Double(payloadBytes / bytesPerSample) / sampleRate
                return PendingRecording(url: url, duration: duration)
            }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// Sample rate as recorded in the WAV header (bytes 24–27), so recovery
    /// duration stays correct whichever engine wrote the file.
    private static func headerSampleRate(of url: URL) -> Double? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: headerByteCount),
              header.count == headerByteCount else {
            return nil
        }
        let value = header[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let sampleRate = Double(UInt32(littleEndian: value))
        return sampleRate > 0 ? sampleRate : nil
    }

    public static func remove(_ pending: PendingRecording) {
        try? FileManager.default.removeItem(at: pending.url)
    }

    private func patchHeaderSizes(on handle: FileHandle) throws {
        let dataSize = UInt32(sampleCount * Self.bytesPerSample)
        let riffSize = UInt32(Self.headerByteCount - 8) + dataSize

        try handle.seek(toOffset: 4)
        try handle.write(contentsOf: Self.bytes(of: riffSize))
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: Self.bytes(of: dataSize))
    }

    private static func header(sampleCount: Int, sampleRate: Double) -> Data {
        let dataSize = UInt32(sampleCount * bytesPerSample)
        let sampleRateValue = UInt32(sampleRate)
        let byteRate = sampleRateValue * UInt32(bytesPerSample)

        var data = Data(capacity: headerByteCount)
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(bytes(of: UInt32(headerByteCount - 8) + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(bytes(of: UInt32(16)))
        data.append(bytes(of: UInt16(1)))
        data.append(bytes(of: UInt16(1)))
        data.append(bytes(of: sampleRateValue))
        data.append(bytes(of: byteRate))
        data.append(bytes(of: UInt16(bytesPerSample)))
        data.append(bytes(of: UInt16(bytesPerSample * 8)))
        data.append(contentsOf: Array("data".utf8))
        data.append(bytes(of: dataSize))
        return data
    }

    private static func bytes<T: FixedWidthInteger>(of value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
