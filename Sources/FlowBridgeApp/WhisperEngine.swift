import AVFoundation
import CoreML
import FlowBridgeShared
import Foundation
import WhisperKit

actor WhisperEngine: TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private var unloadTask: Task<Void, Never>?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var liveSessionID: UUID?
    private var safetyBuffer: AudioSafetyBuffer?
    private var safetyFlushTask: Task<Void, Never>?
    private var lastFlushedSampleCount = 0
    private var isFlushingSamples = false

    private let variant: WhisperModelVariant

    init(variant: WhisperModelVariant = .bundled) {
        self.variant = variant
    }

    func transcribe(recording: RecordedAudio, source: TranscriptRecord.Source) async throws -> TranscriptRecord {
        let kit = try await model()
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            temperature: 0,
            temperatureFallbackCount: 2,
            sampleLength: 224,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            promptTokens: Self.vocabularyPromptTokens(for: kit),
            concurrentWorkerCount: 1,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult]
        do {
            results = try await kit.transcribe(audioPath: recording.url.path, decodeOptions: options)
        } catch {
            throw FlowBridgeError.transcriptionFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        let rawText = results.map(\.text).joined(separator: " ")
        let text = DictationTextNormalizer.normalize(rawText)
        guard !text.isEmpty else {
            throw FlowBridgeError.emptyTranscript
        }

        scheduleIdleUnload()

        return TranscriptRecord(
            text: text,
            language: results.first?.language ?? "und",
            audioDuration: recording.duration,
            source: source
        )
    }

    func startLiveTranscription(sessionID: UUID) async throws {
        guard streamTask == nil else {
            throw FlowBridgeError.alreadyRecording
        }

        let kit = try await model()
        unloadTask?.cancel()
        unloadTask = nil

        guard let tokenizer = kit.tokenizer else {
            throw FlowBridgeError.transcriptionFailed("Tokenizer is not loaded.")
        }

        let liveStore = try LiveTranscriptStore()
        let counter = LiveSequenceCounter()
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

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            temperature: 0,
            temperatureFallbackCount: 2,
            sampleLength: 224,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            promptTokens: Self.vocabularyPromptTokens(for: kit),
            concurrentWorkerCount: 1,
            chunkingStrategy: .vad
        )

        let callback: AudioStreamTranscriberCallback = { _, state in
            let liveText = Self.liveText(from: state)
            try? liveStore.write(
                LiveTranscriptSnapshot(
                    sessionID: sessionID,
                    sequence: counter.next(),
                    text: liveText.committed,
                    previewText: liveText.preview,
                    isRecording: state.isRecording,
                    isFinal: false
                )
            )
        }

        let streamTranscriber = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
            decodingOptions: options,
            requiredSegmentsForConfirmation: 1,
            silenceThreshold: 0.25,
            compressionCheckWindow: 45,
            useVAD: true,
            stateChangeCallback: callback
        )

        self.streamTranscriber = streamTranscriber
        liveSessionID = sessionID
        streamTask = Task {
            do {
                try await streamTranscriber.startStreamTranscription()
            } catch {
                liveStore.writeError(
                    sessionID: sessionID,
                    sequence: counter.next(),
                    message: DictationTextNormalizer.normalize(error.localizedDescription)
                )
            }
        }

        startSafetyFlush(sessionID: sessionID, audioProcessor: kit.audioProcessor)
    }

    func stopLiveTranscription(duration: TimeInterval) async throws -> TranscriptRecord {
        guard let sessionID = liveSessionID else {
            throw FlowBridgeError.notRecording
        }

        streamTranscriber?.stopStreamTranscription()
        streamTask?.cancel()
        streamTask = nil
        streamTranscriber = nil
        liveSessionID = nil

        let liveStore = try LiveTranscriptStore()
        let latestText = liveStore.latest()?.text ?? ""
        let text = DictationTextNormalizer.normalize(latestText)
        guard !text.isEmpty else {
            liveStore.writeFinal(sessionID: sessionID, text: "")
            // Streaming produced nothing. If real audio was captured, keep the
            // safety file so the next launch can retry via file transcription;
            // sub-second recordings hold no speech and are dropped.
            await stopSafetyFlush(
                keepFileForRecovery: duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds
            )
            throw FlowBridgeError.emptyTranscript
        }

        liveStore.writeFinal(sessionID: sessionID, text: text)
        await stopSafetyFlush(keepFileForRecovery: false)
        scheduleIdleUnload()

        return TranscriptRecord(
            text: text,
            language: "und",
            audioDuration: duration,
            source: .microphone
        )
    }

    func unload() async {
        unloadTask?.cancel()
        unloadTask = nil
        // An unload during a live session is an interruption (memory pressure,
        // teardown): keep the safety file so the dictation can be recovered.
        await stopSafetyFlush(keepFileForRecovery: liveSessionID != nil)
        streamTranscriber?.stopStreamTranscription()
        streamTask?.cancel()
        streamTask = nil
        streamTranscriber = nil
        liveSessionID = nil
        guard let whisperKit else { return }
        await whisperKit.unloadModels()
        self.whisperKit = nil
    }

    private func startSafetyFlush(sessionID: UUID, audioProcessor: any AudioProcessing) {
        lastFlushedSampleCount = 0
        guard let directory = try? AudioSafetyBuffer.defaultDirectory() else {
            safetyBuffer = nil
            return
        }

        let buffer = AudioSafetyBuffer(directory: directory)
        safetyBuffer = buffer
        safetyFlushTask = Task {
            try? await buffer.begin(sessionID: sessionID)
            while !Task.isCancelled {
                await flushSafetySamples(from: audioProcessor, into: buffer)
                try? await Task.sleep(for: .seconds(FlowBridgeConstants.safetyBufferFlushInterval))
            }
        }
    }

    private func stopSafetyFlush(keepFileForRecovery: Bool) async {
        safetyFlushTask?.cancel()
        safetyFlushTask = nil

        guard let buffer = safetyBuffer else { return }
        // A loop iteration may still be mid-append (actor methods suspend at
        // awaits); give it a few beats to finish so the final flush below
        // doesn't overlap it and duplicate a sample range.
        var patience = 100
        while isFlushingSamples, patience > 0 {
            patience -= 1
            await Task.yield()
        }
        if let audioProcessor = whisperKit?.audioProcessor {
            await flushSafetySamples(from: audioProcessor, into: buffer)
        }
        if keepFileForRecovery {
            await buffer.closeKeepingFile()
        } else {
            await buffer.completeAndRemove()
        }
        safetyBuffer = nil
        lastFlushedSampleCount = 0
    }

    private func flushSafetySamples(from audioProcessor: any AudioProcessing, into buffer: AudioSafetyBuffer) async {
        // Never two flushes in flight: the counter is only advanced after a
        // successful append, so an overlap would write the same range twice.
        guard !isFlushingSamples else { return }
        isFlushingSamples = true
        defer { isFlushingSamples = false }

        // Single snapshot of the (concurrently appended) sample buffer, with
        // every index derived from that one copy and clamped. WhisperKit
        // synchronizes its own appends; this read is best-effort by design —
        // the safety file tolerates gaps, never corruption.
        let snapshot = audioProcessor.audioSamples
        let count = snapshot.count

        if count < lastFlushedSampleCount {
            // The stream purged already-processed samples. Skipping the purged
            // range leaves a gap in the safety file instead of duplicating
            // audio; a gapped recovery beats a corrupted one.
            lastFlushedSampleCount = count
            return
        }

        guard count > lastFlushedSampleCount else { return }
        let lower = min(lastFlushedSampleCount, count)
        let newSamples = Array(snapshot[lower..<count])
        try? await buffer.append(newSamples)
        lastFlushedSampleCount = count
    }

    /// The user's vocabulary as a Whisper prompt bias: the terms become
    /// decoding context, nudging recognition toward them — the feature the
    /// system dictation and SpeechTranscriber both lack.
    private static func vocabularyPromptTokens(for kit: WhisperKit) -> [Int]? {
        guard let bias = (try? VocabularyStore())?.promptBiasText(),
              let tokenizer = kit.tokenizer else {
            return nil
        }
        let tokens = tokenizer.encode(text: " " + bias)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    private func model() async throws -> WhisperKit {
        if let whisperKit {
            scheduleIdleUnload()
            return whisperKit
        }

        let modelFolder = try WhisperModelLocator.folder(for: variant)
        let compute = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )

        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: modelFolder,
            computeOptions: compute,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )

        let kit = try await WhisperKit(config)
        whisperKit = kit
        scheduleIdleUnload()
        return kit
    }

    private func scheduleIdleUnload() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FlowBridgeConstants.modelIdleTTLSeconds))
            await self?.unload()
        }
    }

    private static func liveText(from state: AudioStreamTranscriber.State) -> (committed: String, preview: String) {
        let confirmed = state.confirmedSegments.map(\.text)
        let unconfirmed = state.unconfirmedSegments.map(\.text)
        let current = state.currentText == "Waiting for speech..." ? "" : state.currentText
        let committed = normalizePieces(confirmed + unconfirmed + [current])
        let preview = normalizePieces(unconfirmed + [current])
        return (committed, preview)
    }

    private static func normalizePieces(_ pieces: [String]) -> String {
        let raw = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return DictationTextNormalizer.normalize(raw)
    }
}
