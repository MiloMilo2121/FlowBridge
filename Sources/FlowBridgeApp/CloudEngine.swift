import AVFoundation
import FlowBridgeShared
import Foundation

/// The only transcription engine: audio is captured locally into the
/// crash-safe AAC file (`AudioSafetyBuffer`) and uploaded once, on stop — no
/// streaming partials. If the upload fails the file is kept, so the next
/// launch re-transcribes it and a dictation is never lost.
///
/// Provider: ElevenLabs Scribe (best independent Italian WER; configure EU
/// Data Residency + Zero Retention on the account, and sign the DPA). The
/// API key lives in the Keychain.
actor CloudEngine {
    private var audioEngine: AVAudioEngine?
    private var safetyBuffer: AudioSafetyBuffer?
    private var encoder: AACEncoder?
    private var safetyFlushTask: Task<Void, Never>?
    private var recordingFileURL: URL?
    private var liveSessionID: UUID?
    private let sampleAccumulator = CloudSampleAccumulator()

    func transcribe(recording: RecordedAudio, source: TranscriptRecord.Source) async throws -> TranscriptRecord {
        let text = try await upload(fileURL: recording.url)
        return TranscriptRecord(
            text: text,
            language: Locale.current.language.languageCode?.identifier ?? "und",
            audioDuration: recording.duration,
            source: source
        )
    }

    func startLiveTranscription(sessionID: UUID) async throws {
        guard audioEngine == nil else {
            throw FlowBridgeError.alreadyRecording
        }
        // No key check here: without one the recording still happens and the file
        // is kept for a later upload, so a meeting is never refused.

        let liveStore = try LiveTranscriptStore()
        liveSessionID = sessionID
        try liveStore.write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: 1,
                text: "",
                previewText: "Cloud dictation — transcript arrives when you stop.",
                isRecording: true,
                isFinal: false
            )
        )

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP, .duckOthers])
        try session.setActive(true, options: [])

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let directory = try AudioSafetyBuffer.defaultDirectory()
        let encoder = try AACEncoder(sampleRate: format.sampleRate)
        let buffer = AudioSafetyBuffer(directory: directory)
        try await buffer.begin(sessionID: sessionID)
        safetyBuffer = buffer
        self.encoder = encoder
        recordingFileURL = AudioSafetyBuffer.fileURL(for: sessionID, in: directory)

        sampleAccumulator.reset(expectedSamplesPerFlush: Int(format.sampleRate * FlowBridgeConstants.safetyBufferFlushInterval))
        safetyFlushTask = Task { [sampleAccumulator] in
            while !Task.isCancelled {
                let pending = sampleAccumulator.drain()
                if !pending.isEmpty {
                    try? await buffer.append(await encoder.encode(pending))
                }
                try? await Task.sleep(for: .seconds(FlowBridgeConstants.safetyBufferFlushInterval))
            }
        }

        let accumulator = sampleAccumulator
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { pcmBuffer, _ in
            if let channel = pcmBuffer.floatChannelData?.pointee {
                accumulator.append(UnsafeBufferPointer(start: channel, count: Int(pcmBuffer.frameLength)))
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    func stopLiveTranscription(duration: TimeInterval) async throws -> TranscriptRecord {
        guard let sessionID = liveSessionID else {
            throw FlowBridgeError.notRecording
        }

        stopCapture()
        liveSessionID = nil

        // Let the flush in progress land first: frames must reach the file in order.
        safetyFlushTask?.cancel()
        await safetyFlushTask?.value
        safetyFlushTask = nil

        guard let buffer = safetyBuffer, let fileURL = recordingFileURL else {
            throw FlowBridgeError.transcriptionFailed("No recording file was produced.")
        }
        try? await finishEncoding(into: buffer)
        // Close but KEEP the file: it is both the upload payload and the
        // crash/offline net.
        await buffer.closeKeepingFile()
        safetyBuffer = nil
        recordingFileURL = nil

        let liveStore = try LiveTranscriptStore()
        do {
            let text = try await upload(fileURL: fileURL)
            liveStore.writeFinal(sessionID: sessionID, text: text)
            try? FileManager.default.removeItem(at: fileURL)
            return TranscriptRecord(
                text: text,
                language: Locale.current.language.languageCode?.identifier ?? "und",
                audioDuration: duration,
                source: .microphone
            )
        } catch {
            // Upload failed (offline, key revoked, provider down): the file
            // stays in the safety folder, so the next launch recovers and
            // re-transcribes this dictation. Nothing is lost.
            liveStore.writeError(sessionID: sessionID, sequence: Int.max, message: "Cloud upload failed — dictation saved for recovery.")
            throw FlowBridgeError.transcriptionFailed(error.localizedDescription)
        }
    }

    func unload() async {
        stopCapture()
        // Let the flush in progress land first: frames must reach the file in order.
        safetyFlushTask?.cancel()
        await safetyFlushTask?.value
        safetyFlushTask = nil
        if let buffer = safetyBuffer {
            try? await finishEncoding(into: buffer)
            // Interrupted session: keep the file for recovery.
            await buffer.closeKeepingFile()
        }
        safetyBuffer = nil
        recordingFileURL = nil
        liveSessionID = nil
    }

    /// Encodes what the tap left and flushes the encoder, so the last words
    /// reach the file.
    private func finishEncoding(into buffer: AudioSafetyBuffer) async throws {
        defer { encoder = nil }
        guard let encoder else { return }
        try await buffer.append(await encoder.encode(sampleAccumulator.drain(), endOfStream: true))
    }

    private func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Upload

    private func upload(fileURL: URL) async throws -> String {
        guard let apiKey = KeychainStore.loadCloudAPIKey() else {
            throw FlowBridgeError.transcriptionFailed("No cloud API key is configured.")
        }
        guard let endpoint = URL(string: FlowBridgeConstants.cloudSpeechToTextURL) else {
            throw FlowBridgeError.transcriptionFailed("Invalid provider endpoint.")
        }

        let boundary = "flowbridge-\(UUID().uuidString)"

        // The multipart body goes to disk and is uploaded with
        // `upload(for:fromFile:)`: a 2-hour meeting is ~60 MB of AAC, and
        // holding the body in memory (plus URLSession's copy) is a jetsam
        // risk. The temp file is removed on every exit.
        // Launch-time recovery sweeps bodies orphaned by a kill mid-upload.
        let bodyURL = AudioSafetyBuffer.uploadBodyURL(for: fileURL)
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        try writeMultipartBody(
            to: bodyURL,
            boundary: boundary,
            audioURL: fileURL
        )

        var request = URLRequest(url: endpoint, timeoutInterval: FlowBridgeConstants.cloudRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Ephemeral session: no caches, no cookies, nothing persisted.
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FlowBridgeError.transcriptionFailed("Provider returned status \(status).")
        }

        struct ScribeResponse: Decodable {
            let text: String
        }
        let decoded = try JSONDecoder().decode(ScribeResponse.self, from: data)
        let text = DictationTextNormalizer.normalize(decoded.text)
        guard !text.isEmpty else {
            throw FlowBridgeError.emptyTranscript
        }
        return text
    }

    /// Streams the multipart body to `bodyURL`: the small fields and headers
    /// in memory, the audio in 1 MB chunks straight from the file. Never holds
    /// the whole payload.
    private func writeMultipartBody(to bodyURL: URL, boundary: String, audioURL: URL) throws {
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }

        func append(_ string: String) throws {
            try output.write(contentsOf: Data(string.utf8))
        }

        try append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model_id\"\r\n\r\n\(FlowBridgeConstants.cloudModelID)\r\n")
        try append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.aac\"\r\nContent-Type: audio/aac\r\n\r\n")

        let input = try FileHandle(forReadingFrom: audioURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }

        try append("\r\n--\(boundary)--\r\n")
    }
}

/// Same shape as the Apple engine's accumulator (single realtime producer,
/// single draining consumer, pre-reserved, O(1) swap under the lock).
private final class CloudSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var reservedCapacity = 0

    func append(_ buffer: UnsafeBufferPointer<Float>) {
        lock.lock()
        samples.append(contentsOf: buffer)
        lock.unlock()
    }

    func drain() -> [Float] {
        var drained: [Float] = []
        drained.reserveCapacity(reservedCapacity)
        lock.lock()
        swap(&drained, &samples)
        lock.unlock()
        return drained
    }

    func reset(expectedSamplesPerFlush: Int) {
        lock.lock()
        reservedCapacity = max(expectedSamplesPerFlush * 2, 4_096)
        samples.removeAll(keepingCapacity: false)
        samples.reserveCapacity(reservedCapacity)
        lock.unlock()
    }
}
