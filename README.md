# FlowBridge

FlowBridge is an on-device-by-default iOS dictation utility. It records instantly, transcribes locally (WhisperKit or Apple's iOS 26 speech stack), cleans the transcript with Apple's on-device model, writes it to the system clipboard, and exposes a lightweight keyboard extension that can insert the most recent transcript.

Privacy posture: everything is on-device and the network is blocked by an in-process guard. The one exception is the **optional cloud engine** — off by default, behind an explicit consent screen, whitelisting exactly one provider host, with a visible badge while it records. Extensions (keyboard/share/widgets) can never reach the network under any configuration.

## Architecture

- The main app is the only target that links WhisperKit or loads CoreML models. Engines are abstracted behind the `TranscriptionEngine` protocol; `WhisperEngine` is the current implementation.
- The keyboard extension never records audio and never loads Whisper. It reads the last transcript from the App Group and inserts it through `UITextDocumentProxy`. Live updates are pushed via Darwin notifications; a slow safety-refresh timer (or the legacy 250ms polling behind a flag) is the fallback.
- Live sessions stream audio into a crash-safe WAV in the App Group (`AudioSafetyBuffer`). Interrupted dictations are recovered and transcribed on the next launch; completed ones delete the file.
- Live mode uses the main app for microphone + Whisper and the keyboard extension for insertion. Keep the FlowBridge keyboard active in the destination app while recording.
- The share extension only queues audio files into the App Group and opens the app. The app performs transcription to avoid extension memory pressure.
- The App Intent opens the app and writes a pending `toggleRecording` command so Action Button and Back Tap shortcuts can trigger the same recording pipeline.
- V2 adds a zero-friction path: `StartDictationIntent` (AudioRecordingIntent) starts recording in the background with a Live Activity in the Dynamic Island (waveform, timer, streaming preview, Stop button), falling back to opening the app when the background start is not viable. The `FlowBridgeWidgets` extension renders the Live Activity plus a Control Center/Lock Screen control and a Home Screen widget. Run `xcodegen generate` once after pulling to materialize the new target in the Xcode project.
- Transcripts are polished on device by Apple's FoundationModels (fillers removed, punctuation fixed); the verbatim transcript is always preserved and every failure path falls back to it.
- WhisperKit is configured with `download: false`. Runtime model downloads are not allowed.

## Build setup

1. Install full Xcode and make it active:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. The generated `FlowBridge.xcodeproj` is committed. Install XcodeGen only when you change `project.yml` and need to regenerate it:

   ```sh
   brew install xcodegen
   ```

3. Fetch and stage the Whisper Small CoreML model:

   ```sh
   ./scripts/fetch-whisper-small.sh
   ```

4. Regenerate the Xcode project after editing `project.yml` **or after adding/renaming source files** (sources are folder-based, so the committed project only knows the files that existed at generation time):

   ```sh
   xcodegen generate
   ```

5. Open `FlowBridge.xcodeproj`, set your development team, and enable the App Group:

   ```text
   group.com.marcomilanello.flowbridge
   ```

## Trigger setup

- Action Button: create a Shortcut that runs the FlowBridge "Toggle Dictation" app intent, then assign it to the Action Button.
- Back Tap: assign the same Shortcut in Settings > Accessibility > Touch > Back Tap.
- Live insertion: add the FlowBridge keyboard in Settings > General > Keyboard and enable Full Access so it can read the App Group live transcript. Open any text field, switch to the FlowBridge keyboard, then trigger dictation with Action Button or Back Tap.
- Manual insertion: tap the insert button on the FlowBridge keyboard to insert the last finished transcript.

## TestFlight and App Store path

FlowBridge is designed as a normal iOS app bundle with a custom keyboard extension and share extension. That makes it suitable for TestFlight and App Store review, as long as the App Store metadata clearly explains:

- speech is captured only after microphone permission and explicit user trigger;
- transcription runs locally on device;
- the keyboard extension needs Full Access only to read the shared local transcript;
- no user speech or transcript data is sent to a server.

## Runtime guarantee

The app fails closed when `Resources/WhisperModels/WhisperSmall` is missing. It does not attempt a model download at runtime.
