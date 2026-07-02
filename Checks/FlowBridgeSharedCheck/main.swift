import FlowBridgeShared
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

let normalized = DictationTextNormalizer.normalize(" hello   world  , flowbridge  ! ")
require(normalized == "Hello world, flowbridge!", "Unexpected normalization: \(normalized)")

let suite = "FlowBridgeSharedCheck.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)

let commandStore = try PendingCommandStore(defaults: defaults)
try commandStore.write(.toggleRecording)
require(commandStore.consume()?.command == .toggleRecording, "Command was not persisted")
require(commandStore.consume() == nil, "Command was not consumed")

let transcriptStore = try TranscriptStore(defaults: defaults)
let record = TranscriptRecord(text: "Hello.", language: "en", audioDuration: 1.2, source: .microphone)
try await transcriptStore.save(record)
let loaded = await transcriptStore.latest()
require(loaded == record, "Transcript was not persisted")
require(TranscriptStore.latest(defaults: defaults) == record, "Synchronous transcript read failed")

let liveStore = try LiveTranscriptStore(defaults: defaults)
let liveSnapshot = LiveTranscriptSnapshot(
    sessionID: UUID(),
    sequence: 1,
    text: "Hello live.",
    previewText: "Hello live.",
    isRecording: true,
    isFinal: false
)
try liveStore.write(liveSnapshot)
require(liveStore.latest() == liveSnapshot, "Live transcript was not persisted")
require(LiveTranscriptStore.latest(defaults: defaults) == liveSnapshot, "Synchronous live read failed")

let wer = WERCalculator.evaluate(
    reference: "il gatto dorme sul divano",
    hypothesis: "il cane dorme divano"
)
require(wer.substitutions == 1, "Expected one substitution, got \(wer.substitutions)")
require(wer.deletions == 1, "Expected one deletion, got \(wer.deletions)")
require(wer.insertions == 0, "Expected zero insertions, got \(wer.insertions)")
require(wer.errorRate == 0.4, "Unexpected WER: \(wer.errorRate)")

let bufferDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("FlowBridgeSharedCheck-SafetyBuffer-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: bufferDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: bufferDirectory) }

let safetyBuffer = AudioSafetyBuffer(directory: bufferDirectory, sampleRate: 16_000)
try await safetyBuffer.begin(sessionID: UUID())
try await safetyBuffer.append([Float](repeating: 0.1, count: 16_000))
await safetyBuffer.closeKeepingFile()

let pending = AudioSafetyBuffer.pendingRecordings(in: bufferDirectory, sampleRate: 16_000)
require(pending.count == 1, "Expected one pending recording, got \(pending.count)")
require(abs(pending[0].duration - 1.0) < 0.001, "Unexpected pending duration: \(pending[0].duration)")

AudioSafetyBuffer.remove(pending[0])
require(AudioSafetyBuffer.pendingRecordings(in: bufferDirectory).isEmpty, "Pending recording was not removed")

print("FlowBridgeSharedCheck passed")
