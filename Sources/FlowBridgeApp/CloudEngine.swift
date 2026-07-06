import AVFoundation
import FlowBridgeShared
import Foundation

/// Opt-in cloud transcription engine (OFF by default).
///
/// Positioning: FlowBridge stays on-device by default; this engine exists
/// for users who deliberately trade "audio never leaves the phone" for the
/// provider's accuracy. Every layer reminds them: explicit consent screen,
/// status badge while recording, and `CloudGate`/`NetworkGuard` whitelisting
/// exactly one host only while the toggle is on.
///
/// Shape: audio is captured LOCALLY into the crash-safe WAV (the same
/// `AudioSafetyBuffer` machinery as the local engines) and uploaded once, on
/// stop — no streaming partials. If the upload fails, the WAV is kept for
/// recovery, so even a cloud dictation is never lost: the next launch
/// re-transcribes it (with whatever engine is then configured).
///
/// Provider: ElevenLabs Scribe (best independent Italian WER; configure EU
/// Data Residency + Zero Retention on the account, and sign the DPA). The
/// API key lives in the Keychain.
actor CloudEngine: TranscriptionEngine {
    private var audioEngine: AVAudioEngine?
    private var safetyBuffer: AudioSafetyBuffer?
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
        guard CloudGate.isCloudEngineEnabled, KeychainStore.loadCloudAPIKey() != nil else {
            throw FlowBridgeError.transcriptionFailed("Cloud engine is not configured.")
        }

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
        let buffer = AudioSafetyBuffer(directory: directory, sampleRate: format.sampleRate)
        try await buffer.begin(sessionID: sessionID)
        safetyBuffer = buffer
        recordingFileURL = directory.appendingPathComponent(sessionID.uuidString).appendingPathExtension("wav")

        sampleAccumulator.reset(expectedSamplesPerFlush: Int(format.sampleRate * FlowBridgeConstants.safetyBufferFlushInterval))
        safetyFlushTask = Task { [sampleAccumulator] in
            while !Task.isCancelled {
                let pending = sampleAccumulator.drain()
                if !pending.isEmpty {
                    try? await buffer.append(pending)
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

        safetyFlushTask?.cancel()
        safetyFlushTask = nil

        guard let buffer = safetyBuffer, let fileURL = recordingFileURL else {
            throw FlowBridgeError.transcriptionFailed("No recording file was produced.")
        }
        let pending = sampleAccumulator.drain()
        if !pending.isEmpty {
            try? await buffer.append(pending)
        }
        // Close but KEEP the WAV: it is both the upload payload and the
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
            // Upload failed (offline, key revoked, provider down): the WAV
            // stays in the safety folder, so the next launch recovers and
            // re-transcribes this dictation. Nothing is lost.
            liveStore.writeError(sessionID: sessionID, sequence: Int.max, message: "Cloud upload failed — dictation saved for recovery.")
            throw FlowBridgeError.transcriptionFailed(error.localizedDescription)
        }
    }

    func unload() async {
        stopCapture()
        safetyFlushTask?.cancel()
        safetyFlushTask = nil
        if let buffer = safetyBuffer {
            let pending = sampleAccumulator.drain()
            if !pending.isEmpty {
                try? await buffer.append(pending)
            }
            // Interrupted session: keep the WAV for recovery.
            await buffer.closeKeepingFile()
        }
        safetyBuffer = nil
        recordingFileURL = nil
        liveSessionID = nil
    }

    private func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Upload

    private func upload(fileURL: URL) async throws -> String {
        guard CloudGate.isCloudEngineEnabled else {
            throw FlowBridgeError.transcriptionFailed("Cloud engine is disabled.")
        }
        guard let apiKey = KeychainStore.loadCloudAPIKey() else {
            throw FlowBridgeError.transcriptionFailed("No cloud API key is configured.")
        }
        guard let endpoint = URL(string: FlowBridgeConstants.cloudSpeechToTextURL) else {
            throw FlowBridgeError.transcriptionFailed("Invalid provider endpoint.")
        }

        let audioData = try Data(contentsOf: fileURL)
        let boundary = "flowbridge-\(UUID().uuidString)"

        var body = Data()
        func appendField(name: String, value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        appendField(name: "model_id", value: FlowBridgeConstants.cloudModelID)
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audioData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint, timeoutInterval: FlowBridgeConstants.cloudRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Ephemeral session: no caches, no cookies, nothing persisted.
        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)

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
