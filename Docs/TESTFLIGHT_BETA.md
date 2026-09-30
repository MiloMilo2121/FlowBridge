# External TestFlight beta handoff

La guida da inviare ai tester è [GUIDA_TESTER.md](GUIDA_TESTER.md). Lo storyboard e le evidenze richieste per il video sono in [VIDEO_DEMO.md](VIDEO_DEMO.md).

## Build gates

1. Verify an active Apple Developer Program team and an App Store Connect app record for `com.marcomilanello.flowbridge`. Register `iCloud.com.marcomilanello.flowbridge` for both the iPhone app and the signed Mac app. A Personal Team can install on a personal device but cannot distribute through TestFlight.
2. Use Xcode 26, free sufficient disk for an archive and the 467 MB bundled Whisper model, and run `xcodegen generate`. Run `swift build`, `swift run FlowBridgeSharedCheck`, the macOS 26 CI build, and iOS simulator tests. Confirm the archived app includes `WhisperModels/WhisperSmall` and the four iOS targets.
3. Install on iPhone Air. Check first run, microphone permission, AssemblyAI key and consent, iCloud account, Action Button, lock screen, killed app, another app playing audio, cloud outage, airplane mode, recovery, and keyboard with Full Access both off and on. Record three timestamps per session: press→Island, press→first word, Stop→clipboard/keyboard.
4. On the Mac, build and sign the linked app with the iCloud entitlement. Before installing it over the working app, verify the Apple Developer team grants the container and that the signature contains the entitlement. Confirm an archived call's original bytes remain unchanged after its iCloud copy appears.
5. Archive with a new `CURRENT_PROJECT_VERSION`, upload to App Store Connect, fill beta description, feedback email and review notes, then add the build to an external tester group. External distribution starts after Apple's beta review.

## Suggested beta description

“Dictate from the Action Button or app. With your own AssemblyAI key, live speech is transcribed through its EU service; local dictation is available too. Your Mac and iPhone diary sync through your iCloud Drive account. Try the Dynamic Island, keyboard, and recovery after a network interruption.”

## Reviewer notes

The first screen offers AssemblyAI cloud or local dictation. Cloud requires the tester's own API key and an explicit consent tap. Local mode needs no provider account. The keyboard types without Full Access; enabling Full Access lets it read transcripts from the local App Group. iCloud Drive requires the same Apple Account on the Mac and iPhone.

## Demo fallback

Prepare a short screen recording with consent, Action Button start, live Island words, Stop, keyboard insertion, Mac diary entry arriving on iPhone, and a deliberate network drop followed by local recovery. Label recorded results with engine and device; never substitute the video for live acceptance testing.
