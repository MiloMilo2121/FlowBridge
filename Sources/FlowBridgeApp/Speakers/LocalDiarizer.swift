import FlowBridgeShared
import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

/// On-device speaker diarization over the session WAV: FluidAudio's pyannote
/// CoreML pipeline on the Neural Engine (~60× realtime). The two models are
/// bundled at build time by `scripts/fetch-diarization-models.sh` — nothing
/// is ever downloaded at runtime (NetworkGuard posture), and a build without
/// the models simply reports unavailable.
actor LocalDiarizer {
    static let shared = LocalDiarizer()

    /// True when this build carries the diarization models.
    static var isAvailable: Bool {
        modelURL(named: "pyannote_segmentation") != nil && modelURL(named: "wespeaker_v2") != nil
    }

    private static func modelURL(named name: String) -> URL? {
        Bundle.main.url(
            forResource: name,
            withExtension: "mlmodelc",
            subdirectory: FlowBridgeConstants.diarizationModelsSubdirectory
        )
    }

#if canImport(FluidAudio)
    private var manager: DiarizerManager?

    /// Who spoke when. Raw speaker IDs come from FluidAudio's clustering
    /// ("1", "2", …); the formatter renumbers them by first appearance.
    func diarize(url: URL) throws -> [SpeakerTranscriptFormatter.Segment] {
        let manager = try loadedManager()
        // The speaker models and Whisper are never resident together. Keep a
        // strong local reference for this pass, then release the actor cache
        // before the precision transcription model is loaded.
        defer { self.manager = nil }
        let started = Date()
        let samples = try AudioConverter().resampleAudioFile(url)
        let result = try manager.performCompleteDiarization(samples)
        let audioSeconds = Double(samples.count) / 16_000
        let elapsed = Date().timeIntervalSince(started)
        FBLog.log("diarizer: \(result.segments.count) segments, \(Set(result.segments.map(\.speakerId)).count) speakers in \(String(format: "%.1f", elapsed))s for \(Int(audioSeconds))s audio")
        return result.segments.map {
            SpeakerTranscriptFormatter.Segment(
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds),
                speaker: $0.speakerId
            )
        }
    }

    func unload() {
        manager = nil
    }

    private func loadedManager() throws -> DiarizerManager {
        if let manager { return manager }
        guard let segmentation = Self.modelURL(named: "pyannote_segmentation"),
              let embedding = Self.modelURL(named: "wespeaker_v2") else {
            throw FlowBridgeError.transcriptionFailed("Diarization models are not bundled in this build.")
        }
        let started = Date()
        let models = try DiarizerModels.load(
            localSegmentationModel: segmentation,
            localEmbeddingModel: embedding
        )
        let loaded = DiarizerManager()
        loaded.initialize(models: models)
        FBLog.log("diarizer: models loaded in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        manager = loaded
        return loaded
    }
#else
    func diarize(url: URL) throws -> [SpeakerTranscriptFormatter.Segment] {
        throw FlowBridgeError.transcriptionFailed("FluidAudio is not part of this build.")
    }

    func unload() {}
#endif
}
