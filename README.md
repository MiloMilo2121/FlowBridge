# FlowBridge

FlowBridge is the team's iPhone recorder. Dictation and meetings (up to 2 hours) are recorded on the
phone into a crash-safe WAV, uploaded for transcription when you stop, and the text lands on the
clipboard. A keyboard extension inserts the latest transcript where you type.

Being rebuilt: transcription moves behind the team's cloud pipeline with Google sign-in, and the UI is
being redesigned. Until then the only engine is `CloudEngine`, which uploads with the provider key
stored in the Keychain.

## Architecture

- The main app records and uploads (`CloudEngine`). Extensions never record and never reach the network.
- Recordings stream into a crash-safe WAV in the App Group (`AudioSafetyBuffer`). An interrupted
  recording is transcribed on the next launch; the file is deleted only once the transcript is stored.
- The keyboard reads the latest transcript from the App Group and inserts it through
  `UITextDocumentProxy`. Live updates arrive via Darwin notifications.
- The share extension only queues audio files into the App Group; the app transcribes them.
- `StartDictationIntent` (AudioRecordingIntent) starts recording in the background with a Live
  Activity in the Dynamic Island. `ToggleDictationIntent` starts or stops it (Action Button).

## Build setup

1. Install Xcode, make it active and run the first launch:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

2. Install XcodeGen (`mise use -g xcodegen@latest`). Regenerate the project after editing
   `project.yml` or adding/renaming source files (sources are folder-based):

   ```sh
   xcodegen generate
   ```

3. Check everything compiles: `./scripts/preflight.sh`.

4. Open `FlowBridge.xcodeproj` and set your development team. The App Group
   `group.com.marcomilanello.flowbridge` is declared in `project.yml` for all four targets.

## Trigger setup

- Action Button: create a Shortcut that runs the FlowBridge "Toggle Dictation" intent and assign it to
  the Action Button.
- Keyboard: add the FlowBridge keyboard in Settings > General > Keyboard and enable Full Access so it
  can read the App Group transcript; tap insert to paste the latest transcript.

## Public repository

This repository is public. Vocabulary, client names, endpoint addresses and the Team ID never go in it.
