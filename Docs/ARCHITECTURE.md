# FlowBridge Architecture

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
