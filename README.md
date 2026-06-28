# FlowBridge

FlowBridge is a local-only iOS dictation utility. It records instantly, runs Whisper Small through CoreML with WhisperKit, writes the cleaned transcript to the system clipboard, and exposes a lightweight keyboard extension that can insert the most recent transcript.

## Architecture

- The main app is the only target that links WhisperKit or loads CoreML models.
- The keyboard extension never records audio and never loads Whisper. It reads the last transcript from the App Group and inserts it through `UITextDocumentProxy`.
- The share extension only queues audio files into the App Group and opens the app. The app performs transcription to avoid extension memory pressure.
- The App Intent opens the app and writes a pending `toggleRecording` command so Action Button and Back Tap shortcuts can trigger the same recording pipeline.
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

4. Regenerate the Xcode project after editing `project.yml`:

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
- Keyboard insertion: add the FlowBridge keyboard in Settings > General > Keyboard. Enable Full Access only if you want the keyboard extension to read the App Group transcript. The keyboard code does not make network requests.

## Runtime guarantee

The app fails closed when `Resources/WhisperModels/WhisperSmall` is missing. It does not attempt a model download at runtime.
