import AVFoundation
import CoreML
import FlowBridgeShared
import Foundation
import WhisperKit

actor WhisperTranscriber {
    private var whisperKit: WhisperKit?
    private var unloadTask: Task<Void, Never>?

    func warmUp() async throws {
        _ = try await model()
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

    func unload() async {
        unloadTask?.cancel()
        unloadTask = nil
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
}

