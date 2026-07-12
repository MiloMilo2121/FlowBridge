import AVFoundation
import FlowBridgeShared
import Foundation
import Speech

/// On-device engine backed by the iOS 26 `SpeechAnalyzer`/`SpeechTranscriber`
/// stack. The model lives in system storage (no app-size or app-memory cost)
/// and posted the best Italian WER in independent 2026 benchmarks.
///
/// NOTE: written against the documented iOS 26 Speech API surface; validate
/// against the SDK in Xcode before shipping (this repo's Linux CI can only
/// build the shared framework).
actor AppleSpeechEngine: TranscriptionEngine {
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var liveSessionID: UUID?
    private var liveCommittedText = ""
    private var liveVolatileText = ""
    private var safetyBuffer: AudioSafetyBuffer?

    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// True when the new transcriber supports and has assets for the locale.
    static func isUsable(locale: Locale = .current) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    func transcribe(recording: RecordedAudio, source: TranscriptRecord.Source) async throws -> TranscriptRecord {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await ensureAssets(for: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task {
            var pieces: [String] = []
            for try await result in transcriber.results where result.isFinal {
                pieces.append(String(result.text.characters))
            }
            return pieces.joined(separator: " ")
        }

        do {
            let audioFile = try AVAudioFile(forReading: recording.url)
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            collector.cancel()
            throw FlowBridgeError.transcriptionFailed(error.localizedDescription)
        }

        let rawText: String
        do {
            rawText = try await collector.value
        } catch {
            throw FlowBridgeError.transcriptionFailed(error.localizedDescription)
        }

        let text = DictationTextNormalizer.normalize(rawText)
        guard !text.isEmpty else {
            throw FlowBridgeError.emptyTranscript
        }

        return TranscriptRecord(
            text: text,
            language: locale.language.languageCode?.identifier ?? "und",
            audioDuration: recording.duration,
            source: source
        )
    }

    func startLiveTranscription(sessionID: UUID) async throws {
        guard audioEngine == nil else {
            throw FlowBridgeError.alreadyRecording
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        try await ensureAssets(for: transcriber)

        let liveStore = try LiveTranscriptStore()
        let counter = LiveSequenceCounter()
        liveSessionID = sessionID
        liveCommittedText = ""
        liveVolatileText = ""
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

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation
        try await analyzer.start(inputSequence: inputStream)

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    await self.handleLiveResult(result, liveStore: liveStore, counter: counter, sessionID: sessionID)
                }
            } catch {
                let message = DictationTextNormalizer.normalize(error.localizedDescription)
                try? liveStore.write(
                    LiveTranscriptSnapshot(
                        sessionID: sessionID,
                        sequence: counter.next(),
                        text: "",
                        previewText: message,
                        isRecording: false,
                        isFinal: true
                    )
                )
            }
        }

        try startCapture(sessionID: sessionID, continuation: continuation)
    }

    func stopLiveTranscription(duration: TimeInterval) async throws -> TranscriptRecord {
        guard let sessionID = liveSessionID else {
            throw FlowBridgeError.notRecording
        }

        stopCapture()
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        liveSessionID = nil

        let liveStore = try LiveTranscriptStore()
        let text = DictationTextNormalizer.normalize(liveCommittedText)
        liveCommittedText = ""
        liveVolatileText = ""

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
            await closeSafetyBuffer(
                keepFileForRecovery: duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds
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
        await closeSafetyBuffer(keepFileForRecovery: false)

        return TranscriptRecord(
            text: text,
            language: locale.language.languageCode?.identifier ?? "und",
            audioDuration: duration,
            source: .microphone
        )
    }

    func unload() async {
        stopCapture()
        inputContinuation?.finish()
        inputContinuation = nil
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        await closeSafetyBuffer(keepFileForRecovery: liveSessionID != nil)
        liveSessionID = nil
        liveCommittedText = ""
        liveVolatileText = ""
    }

    // MARK: - Live results

    private func handleLiveResult(
        _ result: SpeechTranscriber.Result,
        liveStore: LiveTranscriptStore,
        counter: LiveSequenceCounter,
        sessionID: UUID
    ) {
        let piece = String(result.text.characters)
        if result.isFinal {
            liveCommittedText = DictationTextNormalizer.normalize(
                [liveCommittedText, piece].filter { !$0.isEmpty }.joined(separator: " ")
            )
            liveVolatileText = ""
        } else {
            liveVolatileText = DictationTextNormalizer.normalize(piece)
        }

        let combined = DictationTextNormalizer.normalize(
            [liveCommittedText, liveVolatileText].filter { !$0.isEmpty }.joined(separator: " ")
        )
        try? liveStore.write(
            LiveTranscriptSnapshot(
                sessionID: sessionID,
                sequence: counter.next(),
                text: combined,
                previewText: liveVolatileText,
                isRecording: true,
                isFinal: false
            )
        )
    }

    // MARK: - Capture

    private func startCapture(sessionID: UUID, continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP, .duckOthers])
        try session.setActive(true, options: [])

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        if let directory = try? AudioSafetyBuffer.defaultDirectory() {
            let buffer = AudioSafetyBuffer(directory: directory, sampleRate: format.sampleRate)
            safetyBuffer = buffer
            Task { try? await buffer.begin(sessionID: sessionID) }
        }
        let safetyBuffer = safetyBuffer

        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))

            if let channel = buffer.floatChannelData?.pointee {
                let frameCount = Int(buffer.frameLength)
                AudioLevelMeter.shared.ingest(samples: channel, count: frameCount)

                if let safetyBuffer {
                    let samples = Array(UnsafeBufferPointer(start: channel, count: frameCount))
                    Task { try? await safetyBuffer.append(samples) }
                }
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

    // MARK: - Assets

    private func ensureAssets(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
