import AVFoundation
import FlowBridgeShared
import Foundation

/// ElevenLabs Scribe v2 Realtime over websocket: live cloud transcription
/// with ~150ms latency. Capture mirrors `AppleSpeechEngine` (AVAudioEngine
/// tap feeding the level meter and the crash-safety WAV); audio is converted
/// to PCM 16k mono and streamed base64 through the CloudGate session. The
/// server's VAD commits sentences; partials ride as the volatile tail.
///
/// Privacy contract: this engine runs ONLY when the user picked it in
/// Settings; every connection is counted by CloudGate; the API key travels
/// in the `xi-api-key` header, never in the URL, never in logs.
actor CloudScribeRealtimeEngine: TranscriptionEngine {
    private var audioEngine: AVAudioEngine?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var chunkContinuation: AsyncStream<Data>.Continuation?
    private var liveSessionID: UUID?
    private var committedText = ""
    private var volatileText = ""
    private var safetyBuffer: AudioSafetyBuffer?
    private var sessionClosed = false

    private static let sampleRate = 16_000
    /// ~200ms of 16k mono Int16 per websocket message.
    private static let chunkSamples = 3_200

    // MARK: - TranscriptionEngine

    func transcribe(recording: RecordedAudio, source: TranscriptRecord.Source) async throws -> TranscriptRecord {
        let result = try await CloudScribeClient.transcribe(
            fileURL: recording.url,
            language: DictationLanguage.current,
            diarize: SpeakerDetection.isEnabled
        )
        return TranscriptRecord(
            text: result.bestText,
            language: result.languageCode ?? DictationLanguage.current.whisperCode ?? "und",
            audioDuration: recording.duration,
            source: source
        )
    }

    func startLiveTranscription(sessionID: UUID) async throws {
        guard audioEngine == nil else {
            throw FlowBridgeError.alreadyRecording
        }
        guard let apiKey = CloudCredentialsStore.load() else {
            throw FlowBridgeError.transcriptionFailed("No ElevenLabs API key saved — add it in Settings.")
        }

        let liveStore = try LiveTranscriptStore()
        let counter = LiveSequenceCounter()
        liveSessionID = sessionID
        committedText = ""
        volatileText = ""
        sessionClosed = false
        try liveStore.write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: counter.next(),
                text: "",
                previewText: "",
                isRecording: true,
                isFinal: false
            )
        )

        let socket = try openSocket(apiKey: apiKey)
        self.socket = socket
        socket.resume()
        FBLog.log("cloud rt: socket opened")

        startReceiveLoop(socket: socket, liveStore: liveStore, counter: counter, sessionID: sessionID)
        startSendLoop(socket: socket)
        try startCapture(sessionID: sessionID)
    }

    func stopLiveTranscription(duration: TimeInterval) async throws -> TranscriptRecord {
        guard let sessionID = liveSessionID else {
            throw FlowBridgeError.notRecording
        }

        stopCapture()

        // Flush: a short silence tail with commit=true makes the server
        // finalize whatever VAD hasn't committed yet.
        if let socket, !sessionClosed {
            let silence = Data(count: Self.chunkSamples * 2)
            try? await send(chunk: silence, commit: true, over: socket)
            // Give the final committed_transcript a moment to arrive.
            for _ in 0..<30 where !sessionClosed {
                if volatileText.isEmpty && !committedText.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        teardownSocket()
        liveSessionID = nil
        await closeSafetyBuffer(keepFileForRecovery: true)

        let liveStore = try LiveTranscriptStore()
        let text = DictationTextNormalizer.normalize(
            [committedText, volatileText].filter { !$0.isEmpty }.joined(separator: " ")
        )
        committedText = ""
        volatileText = ""

        guard !text.isEmpty else {
            try? liveStore.write(
                LiveTranscriptSnapshot(
                    sessionID: sessionID,
                    sequence: Int.max,
                    text: "",
                    previewText: "",
                    isRecording: false,
                    isFinal: true
                )
            )
            throw FlowBridgeError.emptyTranscript
        }

        try liveStore.write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: Int.max,
                text: text,
                previewText: "",
                isRecording: false,
                isFinal: true
            )
        )

        return TranscriptRecord(
            text: text,
            language: DictationLanguage.current.whisperCode ?? "und",
            audioDuration: duration,
            source: .microphone
        )
    }

    func unload() async {
        FBLog.log("cloud rt: unload (live=\(liveSessionID != nil))")
        stopCapture()
        teardownSocket()
        await closeSafetyBuffer(keepFileForRecovery: liveSessionID != nil)
        liveSessionID = nil
        committedText = ""
        volatileText = ""
    }

    // MARK: - Websocket

    private func openSocket(apiKey: String) throws -> URLSessionWebSocketTask {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
        ]
        if let code = DictationLanguage.current.whisperCode {
            items.append(URLQueryItem(name: "language_code", value: code))
        }
        for term in (try? VocabularyStore())?.terms() ?? [] {
            items.append(URLQueryItem(name: "keyterms", value: term))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw FlowBridgeError.transcriptionFailed("Could not build the realtime endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        CloudGate.noteRequest(host: url.host ?? "api.elevenlabs.io")
        return CloudGate.session(requestTimeout: 15).webSocketTask(with: request)
    }

    private func startReceiveLoop(
        socket: URLSessionWebSocketTask,
        liveStore: LiveTranscriptStore,
        counter: LiveSequenceCounter,
        sessionID: UUID
    ) {
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    guard case .string(let string) = message,
                          let data = string.data(using: .utf8),
                          let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else {
                        continue
                    }
                    handle(event: event, liveStore: liveStore, counter: counter, sessionID: sessionID)
                } catch {
                    if !Task.isCancelled && !sessionClosed {
                        FBLog.log("cloud rt: socket dropped (\(error.localizedDescription))")
                        markStreamDead(
                            message: "Cloud connection lost.",
                            liveStore: liveStore,
                            counter: counter,
                            sessionID: sessionID
                        )
                    }
                    return
                }
            }
        }
    }

    private func handle(
        event: ServerEvent,
        liveStore: LiveTranscriptStore,
        counter: LiveSequenceCounter,
        sessionID: UUID
    ) {
        switch event.messageType {
        case "session_started":
            FBLog.log("cloud rt: session started")
            return
        case "partial_transcript":
            volatileText = DictationTextNormalizer.normalize(event.text ?? "")
        case "committed_transcript", "committed_transcript_with_timestamps":
            let piece = DictationTextNormalizer.normalize(event.text ?? "")
            if !piece.isEmpty {
                committedText = DictationTextNormalizer.normalize(
                    [committedText, piece].filter { !$0.isEmpty }.joined(separator: " ")
                )
            }
            volatileText = ""
        default:
            // Every error type carries `error`.
            if let problem = event.error {
                FBLog.log("cloud rt: server error \(event.messageType): \(problem)")
                markStreamDead(
                    message: problem,
                    liveStore: liveStore,
                    counter: counter,
                    sessionID: sessionID
                )
                return
            }
            return
        }

        let combined = DictationTextNormalizer.normalize(
            [committedText, volatileText].filter { !$0.isEmpty }.joined(separator: " ")
        )
        try? liveStore.write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: counter.next(),
                text: combined,
                previewText: volatileText,
                isRecording: true,
                isFinal: false
            )
        )
    }

    private func markStreamDead(
        message: String,
        liveStore: LiveTranscriptStore,
        counter: LiveSequenceCounter,
        sessionID: UUID
    ) {
        sessionClosed = true
        try? liveStore.write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: counter.next(),
                text: committedText,
                previewText: message,
                isRecording: false,
                isFinal: true
            )
        )
    }

    private func startSendLoop(socket: URLSessionWebSocketTask) {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        chunkContinuation = continuation
        sendTask = Task {
            // A single consumer keeps chunk ordering strict — concurrent
            // sends from the tap thread could interleave audio.
            for await chunk in stream {
                if Task.isCancelled { return }
                try? await send(chunk: chunk, commit: false, over: socket)
            }
        }
    }

    private func send(chunk: Data, commit: Bool, over socket: URLSessionWebSocketTask) async throws {
        struct OutgoingChunk: Encodable {
            let messageType: String
            let audioBase64: String
            let commit: Bool
            let sampleRate: Int

            enum CodingKeys: String, CodingKey {
                case messageType = "message_type"
                case audioBase64 = "audio_base_64"
                case commit
                case sampleRate = "sample_rate"
            }
        }
        let payload = OutgoingChunk(
            messageType: "input_audio_chunk",
            audioBase64: chunk.base64EncodedString(),
            commit: commit,
            sampleRate: Self.sampleRate
        )
        let data = try JSONEncoder().encode(payload)
        guard let string = String(data: data, encoding: .utf8) else { return }
        try await socket.send(.string(string))
    }

    private func teardownSocket() {
        sessionClosed = true
        chunkContinuation?.finish()
        chunkContinuation = nil
        sendTask?.cancel()
        sendTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - Capture (mirrors AppleSpeechEngine)

    private func startCapture(sessionID: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP, .duckOthers])
        try session.setActive(true, options: [])

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw FlowBridgeError.recorderFailed("Could not build the audio converter.")
        }

        if let directory = try? AudioSafetyBuffer.defaultDirectory() {
            let buffer = AudioSafetyBuffer(directory: directory, sampleRate: Double(Self.sampleRate))
            safetyBuffer = buffer
            Task { try? await buffer.begin(sessionID: sessionID) }
        }
        let safetyBuffer = safetyBuffer
        let continuation = chunkContinuation
        var pending = Data()

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            if let channel = buffer.floatChannelData?.pointee {
                AudioLevelMeter.shared.ingest(samples: channel, count: Int(buffer.frameLength))
            }

            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            let inputProvider = SingleBufferConverterInput(buffer: buffer)
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, outStatus in
                inputProvider.next(status: outStatus)
            }
            guard conversionError == nil,
                  converted.frameLength > 0,
                  let int16Channel = converted.int16ChannelData?.pointee else { return }

            let frameCount = Int(converted.frameLength)
            pending.append(Data(bytes: int16Channel, count: frameCount * 2))

            if let safetyBuffer {
                var floats = [Float](repeating: 0, count: frameCount)
                for index in 0..<frameCount {
                    floats[index] = Float(int16Channel[index]) / Float(Int16.max)
                }
                let samples = floats
                Task { try? await safetyBuffer.append(samples) }
            }

            let chunkBytes = Self.chunkSamples * 2
            while pending.count >= chunkBytes {
                continuation?.yield(pending.prefix(chunkBytes))
                pending.removeFirst(chunkBytes)
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    private func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func closeSafetyBuffer(keepFileForRecovery: Bool) async {
        guard let buffer = safetyBuffer else { return }
        if keepFileForRecovery {
            await buffer.closeKeepingFile()
        } else {
            await buffer.completeAndRemove()
        }
        safetyBuffer = nil
    }

    // MARK: - Server events

    private struct ServerEvent: Decodable {
        let messageType: String
        let text: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case text
            case error
        }
    }
}

/// `AVAudioConverter` declares its input callback `@Sendable` even though it
/// invokes it synchronously during `convert`. A locked one-shot provider
/// makes that contract explicit and prevents a captured mutable flag from
/// becoming a Swift 6 data race.
private final class SingleBufferConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var consumed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else {
            status.pointee = .noDataNow
            return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
    }
}
