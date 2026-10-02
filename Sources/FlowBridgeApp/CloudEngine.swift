import AVFoundation
import FlowBridgeShared
import Foundation

/// AssemblyAI EU streaming, with a crash-safe WAV kept until delivery.
actor CloudEngine: TranscriptionEngine {
    private struct Event: Decodable {
        let type: String
        let turn_order: Int?
        let end_of_turn: Bool?
        let transcript: String?
    }

    private var engine: AVAudioEngine?
    private var buffer: AudioSafetyBuffer?
    private var fileURL: URL?
    private var sessionID: UUID?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var flushTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private let samples = CloudSampleAccumulator()
    private var resampler = StreamingResampler(sourceRate: 16_000)
    private var finalTurns: [Int: String] = [:]
    private var partial = ""
    private var partialOrder: Int?
    private var sequence = 0
    private var streamFailed = false
    private var safetyBufferFailed = false
    private var terminated = false

    func transcribe(recording: RecordedAudio, source: TranscriptRecord.Source) async throws -> TranscriptRecord {
        // Recovery never opens a second billable cloud session.
        try await WhisperEngine().transcribe(recording: recording, source: source)
    }

    func startLiveTranscription(sessionID: UUID) async throws {
        guard engine == nil, socket == nil else { throw FlowBridgeError.alreadyRecording }
        guard CloudGate.isCloudEngineEnabled, let key = KeychainStore.loadCloudAPIKey() else {
            throw FlowBridgeError.transcriptionFailed("Configure your AssemblyAI key before cloud dictation.")
        }
        guard let url = URL(string: FlowBridgeConstants.cloudStreamingURL),
              CloudGate.isAllowedWebSocket(url) else {
            throw FlowBridgeError.transcriptionFailed("EU streaming is unavailable.")
        }
        finalTurns = [:]; partial = ""; partialOrder = nil; sequence = 0
        streamFailed = false; safetyBufferFailed = false; terminated = false; samples.reset()

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(key, forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        do {
            let message = try await socket.receive()
            guard case .string(let value) = message,
                  let event = try? JSONDecoder().decode(Event.self, from: Data(value.utf8)),
                  event.type == "Begin" else {
                throw FlowBridgeError.transcriptionFailed("AssemblyAI did not open a session.")
            }
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw error
        }
        self.session = session
        self.socket = socket
        self.sessionID = sessionID
        receiveTask = Task { [weak self] in await self?.receiveLoop() }

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP, .duckOthers])
            try audio.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            resampler = StreamingResampler(sourceRate: format.sampleRate)
            let directory = try AudioSafetyBuffer.defaultDirectory()
            let buffer = AudioSafetyBuffer(directory: directory, sampleRate: format.sampleRate)
            try await buffer.begin(sessionID: sessionID)
            self.buffer = buffer
            fileURL = directory.appendingPathComponent(sessionID.uuidString).appendingPathExtension("wav")
            let accumulator = samples
            input.installTap(onBus: 0, bufferSize: 4_096, format: format) { pcm, _ in
                guard let channel = pcm.floatChannelData?.pointee else { return }
                accumulator.append(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            publish(text: "", preview: "Listening · AssemblyAI EU", isRecording: true)
            flushTask = Task { [weak self] in await self?.flushLoop() }
        } catch {
            await unload()
            throw error
        }
    }

    func stopLiveTranscription(duration: TimeInterval) async throws -> TranscriptRecord {
        guard let id = sessionID, let url = fileURL, let buffer else { throw FlowBridgeError.notRecording }
        stopCapture()
        flushTask?.cancel(); flushTask = nil
        await flushPending()
        await buffer.closeKeepingFile()
        self.buffer = nil; fileURL = nil; sessionID = nil

        if !streamFailed, let socket {
            try? await socket.send(.string("{\"type\":\"ForceEndpoint\"}"))
            for _ in 0..<25 {
                if streamFailed || (partial.isEmpty && !finalTurns.isEmpty) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await socket.send(.string("{\"type\":\"Terminate\"}"))
            for _ in 0..<10 {
                if terminated || streamFailed { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let text = finalTurns.sorted { $0.key < $1.key }.map(\.value).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        closeSocket()
        if !streamFailed, partial.isEmpty, !text.isEmpty {
            try? FileManager.default.removeItem(at: url)
            publish(sessionID: id, text: text, preview: "", isRecording: false, isFinal: true)
            return TranscriptRecord(text: text,
                                    language: Locale.current.language.languageCode?.identifier ?? "und",
                                    audioDuration: duration, source: .microphone)
        }
        publish(sessionID: id, text: "", preview: "Connection lost · finishing on this iPhone",
                isRecording: false)
        if safetyBufferFailed {
            publish(sessionID: id, text: "", preview: "Audio could not be saved for recovery",
                    isRecording: false, isFinal: true)
            throw FlowBridgeError.transcriptionFailed("Cloud transcription failed and the local WAV could not be saved.")
        }
        do {
            let result = try await WhisperEngine().transcribe(
                recording: RecordedAudio(url: url, duration: duration), source: .microphone)
            try? FileManager.default.removeItem(at: url)
            publish(sessionID: id, text: result.text, preview: "", isRecording: false, isFinal: true)
            return result
        } catch {
            publish(sessionID: id, text: "", preview: "Audio saved for recovery",
                    isRecording: false, isFinal: true)
            throw error
        }
    }

    func unload() async {
        stopCapture()
        flushTask?.cancel(); flushTask = nil
        await flushPending()
        await buffer?.closeKeepingFile()
        buffer = nil; fileURL = nil; sessionID = nil
        closeSocket()
    }

    func currentInputLevel() async -> Float { samples.currentLevel }

    private func stopCapture() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func flushLoop() async {
        while !Task.isCancelled {
            await flushPending()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func flushPending() async {
        let batch = samples.drain()
        guard !batch.isEmpty else { return }
        do { try await buffer?.append(batch) }
        catch { safetyBufferFailed = true }
        guard !streamFailed, let socket else { return }
        let data = resampler.convert(batch)
        guard !data.isEmpty else { return }
        do { try await socket.send(.data(data)) }
        catch { streamFailed = true }
    }

    private func receiveLoop() async {
        guard let socket else { return }
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard case .string(let value) = message,
                      let event = try? JSONDecoder().decode(Event.self, from: Data(value.utf8)) else { continue }
                if event.type == "Termination" { terminated = true; return }
                guard event.type == "Turn", let order = event.turn_order else { continue }
                if event.end_of_turn == true {
                    finalTurns[order] = event.transcript ?? ""
                    if partialOrder == order { partial = ""; partialOrder = nil }
                } else {
                    partialOrder = order
                    partial = event.transcript ?? ""
                }
                let stable = finalTurns.sorted { $0.key < $1.key }.map(\.value).joined(separator: " ")
                let live = [stable, partial].filter { !$0.isEmpty }.joined(separator: " ")
                publish(text: live, preview: live, isRecording: true)
            } catch {
                streamFailed = true
                return
            }
        }
    }

    private func publish(sessionID override: UUID? = nil, text: String, preview: String,
                         isRecording: Bool, isFinal: Bool = false) {
        guard let id = override ?? sessionID else { return }
        sequence += 1
        try? LiveTranscriptStore().write(LiveTranscriptSnapshot(
            sessionID: id, sequence: isFinal ? Int.max : sequence, text: text,
            previewText: preview, isRecording: isRecording, isFinal: isFinal))
    }

    private func closeSocket() {
        receiveTask?.cancel(); receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
    }
}

private final class CloudSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Float] = []
    private var level: Float = 0
    var currentLevel: Float { lock.lock(); defer { lock.unlock() }; return level }
    func reset() { lock.lock(); pending.removeAll(); level = 0; lock.unlock() }
    func append(_ input: UnsafeBufferPointer<Float>) {
        lock.lock()
        pending.append(contentsOf: input)
        var sum: Float = 0
        for sample in input { sum += sample * sample }
        level = min(1, sqrt(sum / Float(max(input.count, 1))) * 4)
        lock.unlock()
    }
    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let result = pending
        pending.removeAll(keepingCapacity: true)
        return result
    }
}

private struct StreamingResampler {
    private let step: Double
    private var processed = 0
    private var nextOutput = 0.0
    private var previous: Float = 0
    init(sourceRate: Double) { step = sourceRate / 16_000 }
    mutating func convert(_ input: [Float]) -> Data {
        guard !input.isEmpty else { return Data() }
        let start = processed
        let end = start + input.count
        var output = Data()
        output.reserveCapacity(Int(Double(input.count) / step + 2) * 2)
        while nextOutput <= Double(end - 1) {
            let lower = Int(nextOutput.rounded(.down))
            let upper = lower + 1
            if upper >= end && nextOutput != Double(lower) { break }
            let a = lower < start ? previous : input[lower - start]
            let b = upper < end ? input[upper - start] : a
            let value = a + Float(nextOutput - Double(lower)) * (b - a)
            let sample = Int16((max(-1, min(1, value)) * Float(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: sample) { output.append(contentsOf: $0) }
            nextOutput += step
        }
        previous = input[input.count - 1]
        processed = end
        return output
    }
}
