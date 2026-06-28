# FlowBridge Architecture

## System-wide constraints

iOS does not let a normal app inject arbitrary text into another app's active text field. The system-sanctioned insertion surface is a custom keyboard through `UITextDocumentProxy`, but custom keyboards are the wrong process for microphone capture and a CoreML Whisper Small model. FlowBridge therefore separates the product into a heavy main app and lightweight extensions.

## Trigger model

The primary trigger is an App Intent named "Toggle Dictation". It opens the app and writes a pending command into the App Group. This works with Shortcuts, Action Button, Back Tap, and Siri without putting the model inside an extension.

The main app starts recording immediately and warms the model while the user speaks. When recording stops, the model is usually already loaded or close to loaded.

## Memory model

The app records to disk as 16 kHz mono PCM instead of accumulating microphone buffers. The transcriber is an actor that owns the single WhisperKit instance. It uses:

- `download: false`
- `prewarm: true`
- `load: true`
- `audioEncoderCompute: .cpuAndNeuralEngine`
- `textDecoderCompute: .cpuAndNeuralEngine`
- decode concurrency set to `1`

The model unloads on memory warning and after an idle TTL. Extensions never link WhisperKit.

## Offline posture

Runtime code installs a rejecting `URLProtocol` as a guardrail and never requests remote assets. The release requirement is that Whisper Small and tokenizer files are bundled at build time.

