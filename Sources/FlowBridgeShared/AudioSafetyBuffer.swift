import Foundation

/// Crash-safe audio buffer for live dictation.
///
/// While a live session runs, encoded AAC frames (ADTS, each one readable on
/// its own) are appended to a file in the App Group container, so a session
/// interrupted by a crash or a system kill leaves behind a playable,
/// transcribable file up to the last frame written.
/// Completing a session removes the file; anything found on the next launch
/// is an interrupted dictation to recover.
///
/// Writes are best-effort by design: a safety-buffer failure must never break
/// the live dictation it protects.
public actor AudioSafetyBuffer {
    public struct PendingRecording: Equatable, Sendable {
        public let url: URL
        public let duration: TimeInterval
        /// Recovery attempts already started. The file is renamed *before*
        /// each attempt, so an attempt killed mid-way (jetsam, watchdog)
        /// still counts; this is the count encoded in its name.
        public let recoveryAttempt: Int
        /// When the dictation was recorded (file creation date, preserved
        /// across renames). Nil when the file system can't tell.
        public let recordedAt: Date?

        public init(url: URL, duration: TimeInterval, recoveryAttempt: Int = 0, recordedAt: Date? = nil) {
            self.url = url
            self.duration = duration
            self.recoveryAttempt = recoveryAttempt
            self.recordedAt = recordedAt
        }

        /// Automatic recovery has given up on this file. It stays on disk
        /// until the user retries or discards it by hand.
        public var isExhausted: Bool {
            recoveryAttempt >= FlowBridgeConstants.safetyBufferMaxRecoveryAttempts
        }
    }

    /// Recordings are ADTS AAC files.
    public static let fileExtension = "aac"
    /// Filename marker for a file that already failed recovery N times:
    /// `<uuid>.attempt-N.aac`. Lets the next launch give up on a file no
    /// engine can read, without deleting the user's audio.
    private static let attemptMarker = "attempt-"
    /// Filename marker for a cloud upload body staged next to its recording:
    /// `<uuid>.multipart-XXXXXXXX.tmp`.
    private static let uploadBodyMarker = "multipart-"
    private static let uploadBodyExtension = "tmp"

    private let directory: URL
    private var fileHandle: FileHandle?
    private var fileURL: URL?

    public init(directory: URL) {
        self.directory = directory
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
        let url = Self.fileURL(for: sessionID, in: directory)
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)

        fileHandle = try FileHandle(forWritingTo: url)
        fileURL = url
    }

    public static func fileURL(for sessionID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(sessionID.uuidString).appendingPathExtension(fileExtension)
    }

    /// Appends encoded frames. Each ADTS frame carries its own header, so
    /// the file is valid after every append.
    public func append(_ frames: Data) throws {
        guard let fileHandle, !frames.isEmpty else { return }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: frames)
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

    /// Closes the file handle but leaves the recording on disk. Used when the
    /// session ends without a transcript (unload under pressure, crash paths)
    /// so the next launch can recover the audio.
    public func closeKeepingFile() {
        try? fileHandle?.close()
        fileHandle = nil
        fileURL = nil
    }

    public static func pendingRecordings(in directory: URL) -> [PendingRecording] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == fileExtension }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                guard let size = values?.fileSize else {
                    return nil
                }
                // scorciatoia: duration from size at the target bitrate; exact
                // only for CBR, close enough to show and to skip sub-second files.
                let duration = Double(size) / (FlowBridgeConstants.recordingBitRate / 8)
                return PendingRecording(
                    url: url,
                    duration: duration,
                    recoveryAttempt: recoveryAttempt(of: url),
                    recordedAt: values?.creationDate
                )
            }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    /// Recordings automatic recovery gave up on, newest first: the list the
    /// user retries or discards by hand.
    public static func exhaustedRecordings(in directory: URL) -> [PendingRecording] {
        pendingRecordings(in: directory)
            .filter(\.isExhausted)
            .sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
    }

    /// Where a cloud upload stages the multipart body for `audioURL`: same
    /// directory (same volume, no cross-volume copy), a name that
    /// `pendingRecordings` never lists, and one `removeStaleUploadBodies`
    /// recognizes.
    public static func uploadBodyURL(for audioURL: URL) -> URL {
        audioURL
            .deletingPathExtension()
            .appendingPathExtension("\(uploadBodyMarker)\(UUID().uuidString.prefix(8))")
            .appendingPathExtension(uploadBodyExtension)
    }

    /// Deletes upload bodies orphaned by a kill mid-upload (the uploader's
    /// `defer` never ran). Only files older than `age` go, so an upload in
    /// flight is never pulled from under URLSession; recordings are never touched.
    /// Returns how many were removed.
    @discardableResult
    public static func removeStaleUploadBodies(
        in directory: URL,
        olderThan age: TimeInterval = FlowBridgeConstants.safetyBufferStaleUploadSeconds,
        now: Date = Date()
    ) -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removed = 0
        for url in urls where url.pathExtension == uploadBodyExtension
            && url.deletingPathExtension().pathExtension.hasPrefix(uploadBodyMarker) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) >= age else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// Only call this once the transcript is safely delivered, or when the
    /// user explicitly discards the recording. A file whose recovery failed
    /// is NOT removed: it keeps its attempt count in its name and survives
    /// on disk, past the automatic attempts, until the user decides.
    public static func remove(_ pending: PendingRecording) {
        try? FileManager.default.removeItem(at: pending.url)
    }

    /// Counts a recovery attempt by renaming the file
    /// `<uuid>.aac` → `<uuid>.attempt-N.aac`. Called *before* the attempt,
    /// so a recovery that kills the process still counts and a file no
    /// engine can survive stops being retried. Best-effort: returns the
    /// recording under its new name, or nil when the file could not be
    /// renamed (it stays exactly where it was).
    @discardableResult
    public static func recordRecoveryAttempt(_ pending: PendingRecording) -> PendingRecording? {
        renamed(pending, attempt: pending.recoveryAttempt + 1)
    }

    /// Gives back an attempt that failed for a transient reason (no
    /// network): the audio was never the problem, so it must not bring the
    /// file closer to being given up on.
    @discardableResult
    public static func withdrawRecoveryAttempt(_ pending: PendingRecording) -> PendingRecording? {
        renamed(pending, attempt: max(0, pending.recoveryAttempt - 1))
    }

    /// Clears the count: a user-initiated retry starts from scratch.
    @discardableResult
    public static func resetRecoveryAttempts(_ pending: PendingRecording) -> PendingRecording? {
        renamed(pending, attempt: 0)
    }

    private static func renamed(_ pending: PendingRecording, attempt: Int) -> PendingRecording? {
        guard attempt != pending.recoveryAttempt else { return pending }
        // Rebuild the name from the session id, dropping any previous
        // marker: appending to it would grow the name on every attempt.
        let stem = pending.url.deletingPathExtension().lastPathComponent
        let base = stem.components(separatedBy: ".\(attemptMarker)").first ?? stem
        let name = attempt == 0 ? base : "\(base).\(attemptMarker)\(attempt)"
        let destination = pending.url
            .deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension(pending.url.pathExtension)
        guard FileManager.default.moveItemIfPresent(at: pending.url, to: destination) else {
            return nil
        }
        return PendingRecording(
            url: destination,
            duration: pending.duration,
            recoveryAttempt: attempt,
            recordedAt: pending.recordedAt
        )
    }

    /// Recovery attempts encoded in the filename (0 = never tried). Only
    /// the last component counts, so a session id that happens to contain
    /// the marker cannot be misread.
    private static func recoveryAttempt(of url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        guard let marker = name.range(of: attemptMarker, options: .backwards) else { return 0 }
        return Int(name[marker.upperBound...]) ?? 0
    }

}

private extension FileManager {
    /// `moveItem` that reports success instead of throwing. Recovery paths
    /// are best-effort by design: a failure here must not abort the loop
    /// that is trying to salvage the user's audio.
    func moveItemIfPresent(at source: URL, to destination: URL) -> Bool {
        (try? moveItem(at: source, to: destination)) != nil
    }
}
