import FlowBridgeShared
import Foundation

/// Abstraction over on-device transcription backends.
///
/// V2 routes dictation through interchangeable local engines (WhisperKit
/// today, Apple SpeechTranscriber next). The coordinator and the benchmark
/// harness only speak this protocol, so engines can be swapped and compared
/// without touching the recording pipeline.
protocol TranscriptionEngine: Sendable {
    /// Transcribes a finished audio file (shared audio, safety-buffer recovery,
    /// benchmark cases).
    func transcribe(recording: RecordedAudio, source: TranscriptRecord.Source) async throws -> TranscriptRecord

    /// Starts streaming transcription from the microphone, publishing live
    /// snapshots to the App Group as it goes.
    func startLiveTranscription(sessionID: UUID) async throws

    /// Stops the live session and returns the final transcript.
    func stopLiveTranscription(duration: TimeInterval) async throws -> TranscriptRecord

    /// Releases model memory. Safe to call at any time.
    func unload() async
}
