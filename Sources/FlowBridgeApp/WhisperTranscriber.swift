import AVFoundation
import CoreML
import FlowBridgeShared
import Foundation
import WhisperKit

actor WhisperTranscriber {
    private var whisperKit: WhisperKit?
    private var unloadTask: Task<Void, Never>?
    private var streamTranscriber: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var liveSessionID: UUID?

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
        streamTranscriber?.stopStreamTranscription()
        streamTask?.cancel()
        streamTask = nil
        streamTranscriber = nil
        liveSessionID = nil
        guard let whisperKit else { return }
        await whisperKit.unloadModels()
        self.whisperKit = nil
    }

    private func model() async throws -> WhisperKit {
        if let whisperKit {
            scheduleIdleUnload()
            return whisperKit
        }

        let modelFolder = try bundledModelFolder()
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

    private func bundledModelFolder() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: FlowBridgeConstants.modelFolderName,
            withExtension: nil,
            subdirectory: FlowBridgeConstants.modelResourceSubdirectory
        ) else {
            throw FlowBridgeError.modelMissing(
                "\(FlowBridgeConstants.modelResourceSubdirectory)/\(FlowBridgeConstants.modelFolderName)"
            )
        }

        let requiredFiles = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        for file in requiredFiles {
            let compiled = url.appendingPathComponent(file).appendingPathExtension("mlmodelc")
            let package = url.appendingPathComponent(file).appendingPathExtension("mlpackage")
            if !FileManager.default.fileExists(atPath: compiled.path),
               !FileManager.default.fileExists(atPath: package.path) {
                throw FlowBridgeError.modelMissing(url.path)
            }
        }

        if !FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path) {
            throw FlowBridgeError.modelMissing(url.appendingPathComponent("tokenizer.json").path)
        }

        return url
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
