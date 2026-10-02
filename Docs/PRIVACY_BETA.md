# FlowBridge beta — data and privacy

FlowBridge records after a user starts dictation. When AssemblyAI cloud mode is selected, microphone audio streams to the **EU AssemblyAI endpoint** while recording. Each tester supplies an AssemblyAI API key; FlowBridge stores it in the iPhone Keychain and never includes a shared key in the app. AssemblyAI's account terms and retention settings govern its copy of the audio and transcript.

FlowBridge keeps a local crash-recovery WAV during dictation. It removes the WAV after successful delivery or successful local recovery; if both fail, it keeps the file for another recovery attempt. Whisper and Apple Speech modes process audio locally. Apple's on-device language model may clean text, but the original transcript remains in the local record.

The diary uses the user's **iCloud Drive** account to synchronize between their Mac and iPhone. It contains dictation text, its verbatim form when different, and immutable copies of completed Mac call transcript files. The original Mac call archive is not edited by syncing. When iCloud is unavailable, entries remain local and upload later. Deleting a dictation creates a text-free tombstone so it does not reappear from another device.

The keyboard extension reads completed and live transcripts from the local App Group only when Full Access is granted. It has no networking code. Basic character typing works without Full Access. FlowBridge does not add remote analytics; optional iOS diagnostics stay on the device until the user explicitly shares a report.

Cloud mode and iCloud diary synchronization are distinct services. A tester can select local transcription, but diary synchronization still uses iCloud Drive when available. Never put real customer transcripts or API keys in GitHub issues or beta feedback.
