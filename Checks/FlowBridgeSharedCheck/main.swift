import FlowBridgeShared
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

let normalized = DictationTextNormalizer.normalize(" hello   world  , flowbridge  ! ")
require(normalized == "Hello world, flowbridge!", "Unexpected normalization: \(normalized)")
require(TranscriptIntegrityGuard.accepts(original: "Ehm, ciao ciao Marco.", cleaned: "Ciao Marco."),
        "Safe cleanup was rejected")
require(!TranscriptIntegrityGuard.accepts(original: "Costa 1,3 milioni.", cleaned: "Costa 13 milioni."),
        "A changed number was accepted")

let suite = "FlowBridgeSharedCheck.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)

let commandStore = try PendingCommandStore(defaults: defaults)
try commandStore.write(.toggleRecording)
require(commandStore.consume()?.command == .toggleRecording, "Command was not persisted")
require(commandStore.consume() == nil, "Command was not consumed")

let transcriptStore = try TranscriptStore(defaults: defaults)
let record = TranscriptRecord(text: "Hello.", language: "en", audioDuration: 1.2, source: .microphone)
try transcriptStore.save(record)
let loaded = transcriptStore.latest()
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
require(!liveSnapshot.isError, "A live snapshot must not be flagged as an error")

// The keyboard's live-insert path branches on `isError`: an error snapshot
// carries the message in previewText and an EMPTY text, which must never be
// diffed into the host field.
let errorSession = UUID()
liveStore.writeError(sessionID: errorSession, sequence: 7, message: "Network unavailable.")
let errorSnapshot = LiveTranscriptStore.latest(defaults: defaults)
require(errorSnapshot?.isError == true, "Error snapshot was not flagged: \(String(describing: errorSnapshot))")
require(errorSnapshot?.text.isEmpty == true, "Error snapshot must carry no text")
require(errorSnapshot?.previewText == "Network unavailable.", "Error message was not preserved")

// A final snapshot WITH text is a normal end-of-dictation, not an error.
liveStore.writeFinal(sessionID: errorSession, text: "Ciao.")
require(LiveTranscriptStore.latest(defaults: defaults)?.isError == false, "A final transcript was misread as an error")

// An empty final with no message (the empty-transcript path) is not an
// error either: there is nothing to show and nothing to undo.
liveStore.writeFinal(sessionID: errorSession, text: "")
require(LiveTranscriptStore.latest(defaults: defaults)?.isError == false, "An empty final was misread as an error")

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

// Recovery never destroys the audio: each attempt renames the file with its
// count (before transcribing, so a crash mid-attempt still counts) and it
// stays on disk, so the next launch — or the user — can retry.
let retryBuffer = AudioSafetyBuffer(directory: bufferDirectory, sampleRate: 16_000)
try await retryBuffer.begin(sessionID: UUID())
try await retryBuffer.append([Float](repeating: 0.1, count: 16_000))
await retryBuffer.closeKeepingFile()

let retryPending = AudioSafetyBuffer.pendingRecordings(in: bufferDirectory, sampleRate: 16_000)
require(retryPending.count == 1, "Expected one retryable recording, got \(retryPending.count)")
require(retryPending[0].recoveryAttempt == 0, "A fresh recording must have no attempts")

let marked = AudioSafetyBuffer.recordRecoveryAttempt(retryPending[0])
require(marked != nil, "recordRecoveryAttempt could not rename the file")

let afterFailure = AudioSafetyBuffer.pendingRecordings(in: bufferDirectory, sampleRate: 16_000)
require(afterFailure.count == 1, "A failed recovery must keep the file, got \(afterFailure.count)")
require(afterFailure[0].recoveryAttempt == 1, "Attempt count was not recorded")
require(
    abs(afterFailure[0].duration - 1.0) < 0.001,
    "Renaming must not change the recoverable duration: \(afterFailure[0].duration)"
)

let markedAgain = AudioSafetyBuffer.recordRecoveryAttempt(afterFailure[0])
require(markedAgain?.recoveryAttempt == 2, "Attempt count did not advance")
require(
    AudioSafetyBuffer.pendingRecordings(in: bufferDirectory).count == 1,
    "The recording must survive repeated failures"
)

let commanded = VoiceCommandProcessor.apply(to: "ciao Marco virgola come stai punto interrogativo")
require(commanded == "Ciao Marco, come stai?", "Unexpected voice command output: \(commanded)")

let urlSafe = VoiceCommandProcessor.apply(to: "vai su example.com punto poi scrivi a marco.rossi@example.com virgola grazie")
require(
    urlSafe == "Vai su example.com. Poi scrivi a marco.rossi@example.com, grazie",
    "URLs/emails were mangled: \(urlSafe)"
)

// A bare "punto" is also an ordinary Italian noun: prose must survive it.
let prose = VoiceCommandProcessor.apply(to: "a un certo punto ho cambiato punto di vista")
require(
    prose == "A un certo punto ho cambiato punto di vista",
    "Bare 'punto' in ordinary prose was treated as a command: \(prose)"
)
let proseComma = VoiceCommandProcessor.apply(to: "la virgola divide le frasi")
require(proseComma == "La virgola divide le frasi", "'virgola' as a noun was replaced: \(proseComma)")
// ...while the command itself still works.
let commandedPeriod = VoiceCommandProcessor.apply(to: "prima frase punto seconda frase punto")
require(
    commandedPeriod == "Prima frase. Seconda frase.",
    "A genuine 'punto' command stopped working: \(commandedPeriod)"
)

// Numbering and engine punctuation don't turn the noun into a full stop.
let agenda = VoiceCommandProcessor.apply(to: "passiamo al punto due, a un certo punto, ho deciso")
require(
    agenda == "Passiamo al punto due, a un certo punto, ho deciso",
    "Numbered/punctuated 'punto' was treated as a command: \(agenda)"
)

// A cloud upload body orphaned by a kill is swept; the WAV beside it never is.
let orphan = AudioSafetyBuffer.uploadBodyURL(for: bufferDirectory.appendingPathComponent("orphan.wav"))
try Data("body".utf8).write(to: orphan)
try FileManager.default.setAttributes(
    [.modificationDate: Date().addingTimeInterval(-2 * 60 * 60)],
    ofItemAtPath: orphan.path
)
let survivors = AudioSafetyBuffer.pendingRecordings(in: bufferDirectory).count
require(AudioSafetyBuffer.removeStaleUploadBodies(in: bufferDirectory) == 1, "Orphan upload body was not swept")
require(
    AudioSafetyBuffer.pendingRecordings(in: bufferDirectory).count == survivors,
    "Sweeping upload bodies touched a recording"
)

let vocabulary = try VocabularyStore(defaults: defaults)
try vocabulary.add("Milanello")
require(vocabulary.promptBiasText() == "Glossary: Milanello.", "Unexpected vocabulary bias")

// `requestStart` must not report a dictation that is not running: with no
// handler registered the intent has to fall back to opening the app.
let hub = await MainActor.run { DictationCommandHub.shared }
await MainActor.run { hub.startHandler = nil }
var startThrew = false
do {
    try await hub.requestStart()
} catch let error as FlowBridgeError {
    startThrew = error == .noDictationHandler
} catch {
    startThrew = false
}
require(startThrew, "requestStart reported success with no handler registered")

let invoked = Counter()
await MainActor.run {
    hub.startHandler = { await invoked.increment() }
}
try await hub.requestStart()
let invocations = await invoked.value
require(invocations == 1, "requestStart did not invoke the registered handler")
await MainActor.run {
    hub.startHandler = nil
    hub.stopHandler = nil
    hub.toggleHandler = nil
}

/// Counts invocations across the `MainActor` → handler boundary.
actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

let statsStore = try DictationStatsStore(defaults: defaults)
statsStore.record(text: "una due tre", audioDuration: 3)
require(statsStore.stats().words == 3, "Stats did not accumulate words")

let historyURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("check-history-\(UUID().uuidString).json")
let history = try TranscriptHistoryStore(fileURL: historyURL)
try await history.add(record)
let historyHits = await history.search("hello").count
require(historyHits == 1, "History search failed")
try? FileManager.default.removeItem(at: historyURL)

let toneStore = try ToneContextStore(defaults: defaults)
toneStore.writeHint(ToneHint(profile: .casual))
require(toneStore.currentTone() == .casual, "Tone hint was not honored")

print("FlowBridgeSharedCheck passed")
