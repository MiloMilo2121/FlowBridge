# FlowBridge Architecture

## Engine abstraction (V2 Phase 0)

Transcription backends sit behind the `TranscriptionEngine` protocol
(`Sources/FlowBridgeApp/TranscriptionEngine.swift`). `WhisperEngine` (formerly
`WhisperTranscriber`) is the only implementation today; the V2 roadmap adds an
Apple `SpeechTranscriber` engine behind the same interface. The coordinator and
`BenchmarkHarness` only depend on the protocol, so engines can be swapped and
compared without touching the recording pipeline. `BenchmarkHarness` runs
(audio, reference transcript) pairs from `Resources/Benchmark` through an
engine and reports per-case WER (via `WERCalculator`) and latency.

## Crash-safe audio (V2 Phase 0)

During a live session `WhisperEngine` flushes captured samples once per second
into an `AudioSafetyBuffer` — a 16-bit PCM WAV in the App Group that stays
header-valid after every append. A normal stop deletes the file; an
interruption (crash, memory-pressure unload, empty streaming result on real
audio) leaves it behind, and the coordinator recovers it on the next launch via
file transcription (`TranscriptRecord.Source.recovered`). Safety-buffer writes
are best-effort and can never fail the live dictation they protect. If the
stream purges already-processed samples, the flush skips the purged range: a
gapped recovery beats duplicated audio.

## Keyboard live updates (V2 Phase 0)

`LiveTranscriptStore.write` posts a payload-free Darwin notification
(`FlowBridgeConstants.liveTranscriptDidChangeDarwinName`) after every snapshot.
The keyboard observes it via `DarwinNotificationObserver` and reloads on
delivery instead of polling at 250ms. A slow safety-refresh timer covers missed
notifications; the legacy 250ms polling loop remains available behind
`FlowBridgeConstants.keyboardLegacyPollingEnabled`.

## Recording duration and memory

`maxRecordingSeconds` is 600. At 16kHz mono Float32 the streaming buffer for a
full-length session is ~38MB and the safety-buffer WAV ~19MB — comfortably
inside the main app's budget (extensions never record). The existing
memory-warning handler still stops and finalizes the active transcript before
unloading the model.

## Zero-friction capture path (V2 Phase 1)

`StartDictationIntent` (`AudioRecordingIntent` + `ForegroundContinuableIntent`,
in `Sources/FlowBridgeAppIntents`, compiled into both the app and the widget
extension) starts dictation without opening the app: the system runs it in the
app process, `DictationCommandHub` routes it to `FlowBridgeCoordinator.shared`,
and the coordinator starts the Live Activity synchronously — the platform
requirement for background microphone starts, and our Dynamic Island stage.
When the background path is not viable (no mic permission yet, audio-session
failure) the intent continues in the foreground, which is the V1 behavior.
The same intent powers the Control Center/Lock Screen/Action Button control
and the Home Screen widget; `StopDictationIntent` (`LiveActivityIntent`) backs
the stop button in the island and on the Lock Screen.

The `FlowBridgeWidgets` extension renders the Live Activity
(`DictationActivityAttributes` lives in the shared framework): compact =
phase symbol + self-updating `Text(timerInterval:)`, expanded = streaming
transcript preview + Stop. The coordinator mirrors every live snapshot into
the activity via the same Darwin notification the keyboard uses.

Engines: `EngineFactory` picks WhisperKit (default, V1 behavior) or
`AppleSpeechEngine` (iOS 26 SpeechAnalyzer/SpeechTranscriber, system-managed
model, opt-in via the `preferredEngine` App Group default) — decided by
benchmark, not by taste. After stop, `TranscriptPolisher` (FoundationModels,
on-device) removes fillers and fixes punctuation with guided generation and
greedy sampling; any failure returns the verbatim transcript, which is always
kept in `TranscriptRecord.rawText`. The polisher prewarms while recording so
the cleanup adds no perceptible latency at stop.

## Personal layer (V2 Phases 2–3)

After the engine returns a transcript, the pipeline is: deterministic spoken
commands (`VoiceCommandProcessor`: punto/virgola/a capo/… in Italian and
English, regex whole-word replacements — instant and predictable, never LLM
interpretation) → on-device polish with the current tone. Tone comes from
`ToneContextStore`: the keyboard publishes a hint derived from the active
field's traits (keyboards cannot read the host app's identity via public API;
a "send" return key means a chat box, an email-address field means mail),
falling back to the user's default. The engine-verbatim text always survives
in `rawText`.

`VocabularyStore` holds the user's terms; `WhisperEngine` injects them as a
prompt bias (`promptTokens`) on both file and live decoding — the custom
vocabulary neither system dictation nor SpeechTranscriber offers.
`WhisperModelLocator` adds an optional "Precision" model variant loaded from
Application Support (populated at build time or sideloaded — never a runtime
download, preserving the offline guarantee), with automatic fallback to the
bundled model.

Every finished dictation lands in `TranscriptHistoryStore` (capped local JSON,
pinned entries never evicted, full-text search) and in `DictationStatsStore`
(sessions/words/speaking time → "time given back", computed locally for the
user only). Session Append merges a dictation finished within a configurable
window into the previously delivered text — the clipboard/keyboard get the
continuation, history keeps the individual takes. `HapticPlayer` implements
the fixed haptic vocabulary (listening start/stop, transcript ready, failure)
so the app is fully usable from the pocket.

## System-wide constraints

iOS does not let a normal app inject arbitrary text into another app's active text field. The system-sanctioned insertion surface is a custom keyboard through `UITextDocumentProxy`, but custom keyboards are the wrong process for microphone capture and a CoreML Whisper Small model. FlowBridge therefore separates the product into a heavy main app and lightweight extensions.

## Trigger model

The primary trigger is an App Intent named "Toggle Dictation". It opens the app and writes a pending command into the App Group. This works with Shortcuts, Action Button, Back Tap, and Siri without putting the model inside an extension.

The main app starts streaming transcription immediately. While it records, it writes live transcript snapshots into the App Group. The keyboard extension polls those snapshots and inserts/replaces text in the active field.

## Memory model

The transcriber is an actor that owns the single WhisperKit instance. Live dictation uses WhisperKit's stream transcriber in the app process, never in the keyboard extension. Shared-audio import still uses file-based transcription. The model uses:

- `download: false`
- `prewarm: true`
- `load: true`
- `audioEncoderCompute: .cpuAndNeuralEngine`
- `textDecoderCompute: .cpuAndNeuralEngine`
- decode concurrency set to `1`

The model unloads after an idle TTL. On memory warning during live dictation, the app stops and finalizes the active transcript before unloading. Extensions never link WhisperKit.

## Offline posture

Runtime code installs a rejecting `URLProtocol` as a guardrail and never requests remote assets. The release requirement is that Whisper Small and tokenizer files are bundled at build time.
