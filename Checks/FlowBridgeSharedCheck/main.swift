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

print("FlowBridgeSharedCheck passed")

