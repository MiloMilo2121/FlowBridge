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
