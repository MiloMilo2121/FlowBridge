# FlowBridge

FlowBridge is an iOS dictation utility. After explicit consent and entry of the user's own API key, AssemblyAI Universal-3.5 Pro streams live microphone audio to its EU endpoint by default. Without that setup, WhisperKit transcribes locally. Apple's on-device model can clean the result; the app copies it to the clipboard and its keyboard can insert it.

Privacy posture: the main app opens only the configured AssemblyAI EU streaming host while cloud dictation is enabled. The keyboard, share extension and widgets do not use network APIs. The diary, including immutable copies of completed Mac call transcripts, syncs separately through the user's iCloud Drive account. See [beta privacy details](Docs/PRIVACY_BETA.md).

## Architecture

- The main app is the only target that links WhisperKit or loads CoreML models. Engines are abstracted behind `TranscriptionEngine`; `CloudEngine` streams to AssemblyAI EU and `WhisperEngine` handles local use and cloud failure recovery.
- The keyboard extension never records audio and never loads Whisper. It reads the last transcript from the App Group and inserts it through `UITextDocumentProxy`. Live updates are pushed via Darwin notifications; a slow safety-refresh timer (or the legacy 250ms polling behind a flag) is the fallback.
- Live sessions stream audio into a crash-safe WAV in the App Group (`AudioSafetyBuffer`). Interrupted dictations are recovered and transcribed on the next launch; completed ones delete the file.
- Live mode uses the main app for microphone and transcription and the keyboard extension for insertion. Keep the FlowBridge keyboard active in the destination app while recording.
- The share extension only queues audio files into the App Group and opens the app. The app performs transcription to avoid extension memory pressure.
- The App Intent opens the app and writes a pending `toggleRecording` command so Action Button and Back Tap shortcuts can trigger the same recording pipeline.
- `StartDictationIntent` (AudioRecordingIntent) starts recording in the background with a Live Activity in the Dynamic Island, falling back to opening the app when the background start is not viable. The `FlowBridgeWidgets` extension renders the Live Activity plus a Control Center/Lock Screen control and a Home Screen widget. Run `xcodegen generate` after source or project changes.
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

5. Open `FlowBridge.xcodeproj`, set your development team, and register the App Group and iCloud Documents container in the Apple Developer account:

   ```text
   group.com.marcomilanello.flowbridge
   iCloud.com.marcomilanello.flowbridge
   ```

## Trigger setup

- Action Button: create a Shortcut that runs the FlowBridge "Toggle Dictation" app intent, then assign it to the Action Button.
- Back Tap: assign the same Shortcut in Settings > Accessibility > Touch > Back Tap.
- Live insertion: add the FlowBridge keyboard in Settings > General > Keyboard and enable Full Access so it can read the App Group live transcript. Basic typing works without Full Access. Open any text field, switch to the FlowBridge keyboard, then trigger dictation with Action Button or Back Tap.
- Manual insertion: tap the insert button on the FlowBridge keyboard to insert the last finished transcript.

## TestFlight and App Store path

FlowBridge is designed as a normal iOS app bundle with a custom keyboard extension and share extension. That makes it suitable for TestFlight and App Store review, as long as the App Store metadata clearly explains:

- speech is captured only after microphone permission and explicit user trigger;
- local transcription and cloud failure recovery run on device;
- the keyboard extension needs Full Access only to read the shared local transcript;
- cloud dictation streams audio to AssemblyAI EU only after consent and key setup; diary text syncs through the user's iCloud Drive account;
- local mode and the keyboard extension do not send speech to a transcription provider.

For the second Mac setup see [SECONDO_MAC.md](Docs/SECONDO_MAC.md); beta review gates are in [TESTFLIGHT_BETA.md](Docs/TESTFLIGHT_BETA.md). Send [GUIDA_TESTER.md](Docs/GUIDA_TESTER.md) to testers. The on-device video shot list is [VIDEO_DEMO.md](Docs/VIDEO_DEMO.md).

## Runtime guarantee

The app does not download Whisper models at runtime. The bundled model is required for local dictation and cloud failure recovery.
