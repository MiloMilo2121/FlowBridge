import FlowBridgeShared
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class FlowBridgeCoordinator: ObservableObject {
    /// Single instance shared by the SwiftUI scene and by App Intents, which
    /// the system executes in this same process (AudioRecordingIntent /
    /// LiveActivityIntent) and which must reach the live audio session.
    static let shared = FlowBridgeCoordinator()

    /// The pipeline's real phases, published as they happen. UI-only: the
    /// coordinator's state machine is untouched, these ride on top of it.
    enum ProcessingStage: Equatable {
        case finalizingAudio
        case decodingSpeech
        case refiningText
        case delivering

        var label: String {
            switch self {
            case .finalizingAudio: return "Closing audio…"
            case .decodingSpeech: return "Decoding speech…"
            case .refiningText: return "Refining…"
            case .delivering: return "Delivering…"
            }
        }
    }

    /// What went wrong, said like a person, plus the single tap that fixes
    /// it. Recoverable errors contract the field; they never blank the room.
    struct FlowErrorPresentation: Equatable {
        enum Recovery: Equatable {
            case openSettings
            case tryAgain
            case recoverInterrupted

            var title: String {
                switch self {
                case .openSettings: return "Open Settings"
                case .tryAgain: return "Try Again"
                case .recoverInterrupted: return "Recover Audio"
                }
            }
        }

        let title: String
        let message: String
        let symbol: String
        let recovery: Recovery?
    }

    enum State: Equatable {
        case idle
        case warming
        case recording(startedAt: Date)
        case transcribing
        case ready
        case failed(String)
    }

    /// The raw→polished transformation of the take that just finished — the
    /// payoff moment the transcript panel animates. Nil when polish left the
    /// text untouched.
    struct PolishReveal: Equatable {
        let raw: String
        let polished: String
        /// Words removed by the polish (negative when it added words).
        let wordsDelta: Int

        init?(record: TranscriptRecord) {
            guard let raw = record.rawText, raw != record.text else { return nil }
            self.raw = raw
            self.polished = record.text
            let rawWords = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let polishedWords = record.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            self.wordsDelta = rawWords - polishedWords
        }
    }

    @Published private(set) var state: State = .idle
    /// Dictate delivers text only. Act delivers the same text first, then
    /// looks for one explicit system action. Persisted across launches and
    /// switchable from the app or Dynamic Island.
    @Published private(set) var voiceMode: VoiceMode = .current
    /// Set while the live session is paused (engine mic gated, timers
    /// frozen). Recording state is preserved underneath.
    @Published private(set) var pausedAt: Date?
    @Published private(set) var lastTranscript: TranscriptRecord?
    @Published private(set) var statusMessage: String?
    @Published private(set) var recordingElapsed: TimeInterval?
    /// Live words as they stream in, for the in-app transcript view.
    @Published private(set) var liveTranscript: LiveTranscriptSnapshot?
    /// Set when a finished take was visibly improved by the polisher.
    @Published private(set) var polishReveal: PolishReveal?
    /// Unusual words from the last take, offered as one-tap vocabulary chips.
    @Published private(set) var vocabularySuggestions: [String] = []
    /// "Time given back" total, refreshed after every session (the ticker
    /// in the Flow Rail counts up to it).
    @Published private(set) var timeSavedMinutes: Double = 0
    /// Consecutive dictation days, and whether the last session opened a
    /// new day (drives the streak celebration).
    @Published private(set) var streakDays: Int = 0
    @Published private(set) var isNewStreakDay: Bool = false
    /// One-tap action detected in the delivered text ("tomorrow lunch with
    /// Luca" → Calendar Event). Nil for plain dictations.
    @Published private(set) var suggestedAction: SuggestedAction?
    /// Narrates what the pipeline is actually doing between stop and ready —
    /// four real micro-stages instead of one opaque "Transcribing".
    @Published private(set) var processingStage: ProcessingStage?
    /// Structured error for the UI: what happened, and the one tap that
    /// fixes it. The screen stays alive underneath.
    @Published private(set) var errorPresentation: FlowErrorPresentation?
    /// Transient "Added to Calendar"-style confirmation after a performed
    /// action, in the slot the suggestion chip occupied.
    @Published private(set) var actionConfirmation: String?

    private let recorder = FlowBridgeRecorder()
    /// Engines are cached per preference and resolved at session start, so
    /// the Settings picker applies from the next dictation — no app relaunch.
    private var engineCache: [EnginePreference: any TranscriptionEngine] = [:]
    /// Permission and model warmup both suspend. This gate closes the window
    /// where a rapid UI + Action Button pair could launch two audio starts.
    private var recordingStartGate = AsyncOperationGate()
    private var activeEnginePreference = EnginePreference.current
    private var transcriber: any TranscriptionEngine {
        cachedEngine(for: activeEnginePreference)
    }
    private let activityController = DictationActivityController()
    private let polisher = TranscriptPolisher.shared
    private let recordingFeedback = RecordingFeedbackDriver()
    private let finalPass = FinalPassService()
    private var transcriptStore: TranscriptStore?
    private var historyStore: TranscriptHistoryStore?
    private var statsStore: DictationStatsStore?
    private var toneStore: ToneContextStore?
    private var pendingCommandStore: PendingCommandStore?
    private var elapsedTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var confirmationDismissTask: Task<Void, Never>?
    /// History id of the take the current suggestion was computed from, so a
    /// performed action can be stamped on the right record.
    private var suggestionRecordID: UUID?
    /// The individual take (not a session-appended merge) that Act mode may
    /// interpret after delivery.
    private var lastActionCandidateText: String?
    private var islandTask: Task<Void, Never>?
    private var lastSentIslandState: DictationActivityAttributes.ContentState?
    /// Silence guard: the loudest level seen this session, and whether we've
    /// already nudged the user. A dead mic (route stuck, another app holding
    /// it, silent Bluetooth) makes Whisper hallucinate on nothing; better to
    /// say so than to deliver "I love you" in the transcript.
    private var sessionPeakLevel: Float = 0
    private var silenceHintShown = false
    /// When the mic actually began delivering (first recording tick, after
    /// warming) — the clock the silence guard measures against, so a slow
    /// model load never counts as silence.
    private var micTicksStartedAt: Date?
    /// Guards snapshot readers: after a crash the App Group can still hold a
    /// `isRecording` snapshot from the dead session, which must never leak
    /// into a new session's island or live view.
    private var currentSessionID: UUID?
    /// Darwin notifications coalesce poorly: the same snapshot can arrive
    /// several times back-to-back. Sequences at or below this are ignored.
    private var lastSeenSnapshotSequence = 0
    private var memoryWarningObserver: NSObjectProtocol?
    private var commandObserver: DarwinNotificationObserver?
    private var liveSnapshotObserver: DarwinNotificationObserver?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleMemoryWarning()
            }
        }
    }

    // No deinit: this is a process-lifetime singleton (`shared`) that is
    // never deallocated, so the memory-warning observer and timers live as
    // long as the app. A nonisolated deinit also can't touch the
    // non-Sendable observer under Swift 6 strict concurrency.

    func bootstrap() async {
        FBLog.rotateIfNeeded()
        FBLog.log("bootstrap: engine=\(type(of: transcriber))")
        NetworkGuard.install()
        transcriptStore = try? TranscriptStore()
        historyStore = try? TranscriptHistoryStore()
        statsStore = try? DictationStatsStore()
        toneStore = try? ToneContextStore()
        pendingCommandStore = try? PendingCommandStore()
        lastTranscript = await transcriptStore?.latest()
        refreshStatsSummary()

        registerSystemIntegration()
        // A crash mid-recording leaves an orphaned Live Activity that this
        // process no longer tracks; kill it before recovery narrates its own
        // story.
        activityController.endAllActivities()
        await recoverInterruptedDictationIfNeeded()
        await consumePendingCommand()
        await processQueuedAudioIfNeeded()
    }

    private func refreshStatsSummary() {
        guard let statsStore else { return }
        timeSavedMinutes = statsStore.stats().timeSavedMinutes
        streakDays = statsStore.currentStreak()
    }

    // MARK: - Engine resolution (hot switch)

    private func cachedEngine(for preference: EnginePreference) -> any TranscriptionEngine {
        if let cached = engineCache[preference] {
            return cached
        }
        let engine = EngineFactory.make(preference)
        engineCache[preference] = engine
        return engine
    }

    /// Reads the Settings preference at session start; a change unloads the
    /// previous engine's memory and takes effect immediately.
    @discardableResult
    private func resolveEngine() async -> any TranscriptionEngine {
        let preference = EnginePreference.current
        if preference != activeEnginePreference {
            FBLog.log("engine switch: \(activeEnginePreference.rawValue) → \(preference.rawValue)")
            if let previous = engineCache[activeEnginePreference] {
                await previous.unload()
            }
            activeEnginePreference = preference
        }
        return cachedEngine(for: preference)
    }

    /// Wires App Intents and cross-process wakeups to this coordinator.
    private func registerSystemIntegration() {
        DictationCommandHub.shared.startHandler = { [weak self] in
            try await self?.startBackgroundDictation()
        }
        DictationCommandHub.shared.stopHandler = { [weak self] in
            await self?.stopIfRecording()
        }
        DictationCommandHub.shared.toggleHandler = { [weak self] in
            await self?.toggleRecording()
        }
        DictationCommandHub.shared.pauseHandler = { [weak self] in
            await self?.pauseDictation()
        }
        DictationCommandHub.shared.resumeHandler = { [weak self] in
            await self?.resumeDictation()
        }
        DictationCommandHub.shared.applyToneHandler = { [weak self] raw in
            await self?.applyToneVariant(raw)
        }
        DictationCommandHub.shared.setVoiceModeHandler = { [weak self] mode in
            await self?.setVoiceMode(mode)
        }
        DictationCommandHub.shared.toggleVoiceModeHandler = { [weak self] in
            guard let self else { return }
            let next: VoiceMode = self.voiceMode == .act ? .dictate : .act
            await self.setVoiceMode(next)
        }
        DictationCommandHub.shared.performSuggestedActionHandler = { [weak self] in
            await self?.performSuggestedAction()
        }

        // Pending commands can be written while the app is backgrounded under
        // an active audio session (e.g. from the keyboard or a fallback
        // intent path); react immediately instead of waiting for foreground.
        commandObserver = DarwinNotificationObserver(
            name: FlowBridgeConstants.pendingCommandDidChangeDarwinName
        ) {
            Task { @MainActor in
                await FlowBridgeCoordinator.shared.consumePendingCommand()
            }
        }

        // Live transcript snapshots feed the in-app streaming view; the
        // Dynamic Island reads the store on its own fixed tick instead, so
        // one combined update carries text + waveform levels.
        liveSnapshotObserver = DarwinNotificationObserver(
            name: FlowBridgeConstants.liveTranscriptDidChangeDarwinName
        ) {
            Task { @MainActor in
                FlowBridgeCoordinator.shared.handleLiveSnapshot()
            }
        }
    }

    private func handleLiveSnapshot() {
        guard case .recording = state else { return }
        guard let snapshot = LiveTranscriptStore.latest(),
              snapshot.sessionID == currentSessionID,
              snapshot.sequence > lastSeenSnapshotSequence else { return }
        lastSeenSnapshotSequence = snapshot.sequence
        FBLog.log("snapshot seq=\(snapshot.sequence) rec=\(snapshot.isRecording) final=\(snapshot.isFinal) text=\(snapshot.text.count)ch preview=\(snapshot.previewText.prefix(60))")

        if snapshot.isRecording {
            liveTranscript = snapshot
            recordingFeedback.noteSnapshot(snapshot)
        } else if snapshot.isFinal {
            // The engine's stream died mid-session: it writes a final
            // snapshot carrying the error in previewText. Without this
            // branch the app stays in a zombie "Listening" state.
            let message = snapshot.previewText
            Task { await self.handleEngineStreamDeath(message: message) }
        }
    }

    private func handleEngineStreamDeath(message: String) async {
        guard case .recording = state, currentSessionID != nil else { return }
        currentSessionID = nil
        FBLog.log("engine stream died: \(message)")
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        stopIslandTick()
        recordingFeedback.stop()
        recordingElapsed = nil
        currentSessionID = nil
        liveTranscript = nil
        await transcriber.unload()
        let text = message.isEmpty ? "The engine stopped unexpectedly." : message
        activityController.finish(transcriptPreview: text, startedAt: Date(), failed: true)
        fail(FlowBridgeError.transcriptionFailed(text))
    }

    /// Start requested by `StartDictationIntent` while the app may be
    /// backgrounded: no permission prompt is possible there, and the Live
    /// Activity must be up for as long as the recording runs (the system
    /// stops background audio otherwise). Throws when the background path is
    /// not viable so the intent can fall back to opening the app.
    func startBackgroundDictation() async throws {
        if recordingStartGate.isEntered { return }
        switch state {
        case .recording, .warming:
            return
        case .transcribing:
            throw FlowBridgeError.alreadyRecording
        case .idle, .ready, .failed:
            break
        }
        guard await recorder.hasGrantedPermission() else {
            throw FlowBridgeError.microphonePermissionDenied
        }

        await startRecording(requestPermission: false)

        guard case .recording = state else {
            throw FlowBridgeError.recorderFailed(statusMessage ?? "Background start failed.")
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        FBLog.log("scenePhase=\(phase) state=\(state)")
        switch phase {
        case .active:
            await consumePendingCommand()
            await processQueuedAudioIfNeeded()
        case .background:
            switch state {
            case .recording, .warming, .transcribing:
                // The session owns the engine: unloading here would kill the
                // live stream (the actor interleaves the unload right after
                // start).
                statusMessage = "Live bridge active"
            case .idle, .ready, .failed:
                await transcriber.unload()
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    /// `flowbridge://record` — the URL entry point (Lock Screen widget,
    /// Shortcuts "Open URL"). Routed through the same pending-command store
    /// the intents use, so the cold-start race is handled once.
    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "flowbridge" else { return }
        switch url.host ?? url.lastPathComponent {
        case "record":
            FBLog.log("deeplink: record")
            try? PendingCommandStore().write(.toggleRecording)
        default:
            break
        }
    }

    func consumePendingCommand() async {
        // Falls back to a fresh store when called before `bootstrap()` has
        // assigned one — e.g. a cold start from the Lock Screen widget's
        // deep link, whose onOpenURL can race the bootstrap task.
        let store = pendingCommandStore ?? (try? PendingCommandStore())
        guard let command = store?.consume()?.command else { return }
        FBLog.log("pending command consumed: \(command)")

        switch command {
        case .toggleRecording:
            await toggleRecording()
        case .stopRecording:
            await stopIfRecording()
        case .transcribeQueuedAudio:
            await processQueuedAudioIfNeeded()
        case .pauseRecording:
            await pauseDictation()
        case .resumeRecording:
            await resumeDictation()
        }
    }

    func toggleRecording() async {
        switch state {
        case .recording:
            await stopRecordingAndTranscribe()
        case .transcribing, .warming:
            break
        case .idle, .ready, .failed:
            await startRecording()
        }
    }

    func requestMicrophonePermission() async -> Bool {
        await recorder.requestPermission()
    }

    var history: TranscriptHistoryStore? { historyStore }
    var stats: DictationStatsStore? { statsStore }
    var toneContext: ToneContextStore? { toneStore }
    var canPauseCurrentSession: Bool { activeEnginePreference != .cloudRealtime }

    func copyLastTranscript() async {
        guard let text = lastTranscript?.text else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Changes only the interpretation lens, never the recognition pipeline.
    /// It is therefore safe to switch mid-recording from the Dynamic Island.
    func setVoiceMode(_ mode: VoiceMode) async {
        guard voiceMode != mode else { return }
        voiceMode = mode
        mode.save()
        FBLog.log("voice mode: \(mode.rawValue)")
        UISelectionFeedbackGenerator().selectionChanged()

        if mode == .dictate {
            suggestionTask?.cancel()
            suggestionTask = nil
            suggestedAction = nil
            activityController.clearSuggestedAction()
        }

        if case .recording(let startedAt) = state {
            if pausedAt == nil {
                pushIslandUpdate(startedAt: startedAt)
            } else {
                pushPausedIslandState(startedAt: startedAt)
            }
        } else if case .ready = state {
            activityController.setAssistantMode(mode == .act)
            if mode == .act,
               let text = lastActionCandidateText,
               let recordID = suggestionRecordID {
                scheduleActionDiscovery(text: text, recordID: recordID)
            }
        }
    }

    func unloadModel() async {
        await transcriber.unload()
        statusMessage = "Model unloaded"
    }

    private func startRecording(requestPermission: Bool = true) async {
        guard recordingStartGate.enterIfAvailable() else {
            FBLog.log("start: duplicate request ignored")
            return
        }
        defer { recordingStartGate.leave() }

        switch state {
        case .idle, .ready, .failed:
            break
        case .warming, .recording, .transcribing:
            FBLog.log("start: ignored while state=\(state)")
            return
        }

        do {
            if requestPermission {
                guard await recorder.requestPermission() else {
                    throw FlowBridgeError.microphonePermissionDenied
                }
            } else {
                guard await recorder.hasGrantedPermission() else {
                    throw FlowBridgeError.microphonePermissionDenied
                }
            }

            let startedAt = Date()
            let sessionID = UUID()
            state = .warming
            // The very first load compiles the model for the Neural Engine
            // and can take up to a minute; afterwards it's near-instant.
            statusMessage = "Preparing engine — first run can take a minute"
            polishReveal = nil
            liveTranscript = nil
            vocabularySuggestions = []
            // A previous take may still be classifying in Foundation Models.
            // Cancellation is cooperative, so drain it and drop every idle
            // language-model session before loading a speech model.
            let pendingSuggestion = suggestionTask
            suggestionTask = nil
            await TaskQuiescer.cancelAndWait(pendingSuggestion)
            await IntentClassifier.shared.releaseSession()
            await polisher.releaseSession()
            confirmationDismissTask?.cancel()
            confirmationDismissTask = nil
            suggestedAction = nil
            actionConfirmation = nil
            errorPresentation = nil
            processingStage = nil
            currentSessionID = sessionID
            lastSeenSnapshotSequence = 0
            sessionPeakLevel = 0
            silenceHintShown = false
            micTicksStartedAt = nil
            AudioLevelMeter.shared.reset()
            HapticPlayer.prepare()
            // The Live Activity goes up before the engine warms: the island
            // responds to the trigger instantly, and background starts via
            // AudioRecordingIntent require a visible activity to keep audio.
            activityController.start(
                sessionID: sessionID,
                startedAt: startedAt,
                assistantMode: voiceMode == .act
            )
            let engine = await resolveEngine()
            FBLog.log("start: warming, engine=\(type(of: engine)) session=\(sessionID.uuidString.prefix(8))")
            var usedLocalFallback = false
            do {
                try await engine.startLiveTranscription(sessionID: sessionID)
            } catch where activeEnginePreference == .cloudRealtime {
                // Cloud unreachable (no network, bad key, server down): the
                // dictation must still happen. Local fallback for THIS
                // session; next start re-reads the preference and retries.
                FBLog.log("start: cloud realtime unavailable (\(error)) — local fallback")
                activeEnginePreference = .whisper
                try await cachedEngine(for: .whisper).startLiveTranscription(sessionID: sessionID)
                usedLocalFallback = true
            }
            FBLog.log("start: recording")
            state = .recording(startedAt: startedAt)
            statusMessage = usedLocalFallback ? "Cloud unreachable — dictating on-device" : "Live bridge active"
            startElapsedTimer(from: startedAt)
            startMaxDurationTimer()
            startIslandTick(startedAt: startedAt)
            recordingFeedback.start()
            HapticPlayer.listeningStarted()
            // Do not prewarm Foundation Models during a live take. The
            // speech model owns the memory envelope until stop, then hands it
            // off explicitly to final-pass and cleanup models.
        } catch {
            FBLog.log("start FAILED: \(error)")
            currentSessionID = nil
            // Narrate the failure in the island instead of vanishing it.
            activityController.markFailed(message: Self.errorMessage(for: error), startedAt: Date())
            fail(error)
        }
    }

    /// One combined Live Activity update per tick — waveform levels plus the
    /// streaming text — replacing the unthrottled per-snapshot push (which
    /// peaked at 5–10Hz on the Apple engine). 4Hz for the first two seconds
    /// so the island reacts to the trigger instantly, then 2Hz; identical
    /// states are skipped, so silence costs zero updates.
    private func startIslandTick(startedAt: Date) {
        islandTask?.cancel()
        lastSentIslandState = nil
        islandTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                self?.pushIslandUpdate(startedAt: startedAt)
                tick += 1
                try? await Task.sleep(for: .milliseconds(tick < 8 ? 250 : 500))
            }
        }
    }

    private func stopIslandTick() {
        islandTask?.cancel()
        islandTask = nil
        lastSentIslandState = nil
    }

    private func pushIslandUpdate(startedAt: Date) {
        guard case .recording = state, activityController.isActive else { return }
        // Silence guard: a stuck input route (or another app / silent
        // Bluetooth) delivers near-zero audio, and Whisper then hallucinates
        // on nothing. Measure from the first recording tick (not session
        // start — a slow model load isn't silence); if only silence has
        // arrived after a few seconds, and we're not paused, say so once.
        let now = Date()
        if micTicksStartedAt == nil { micTicksStartedAt = now }
        sessionPeakLevel = max(sessionPeakLevel, AudioLevelMeter.shared.latestLevel)
        if !silenceHintShown, pausedAt == nil,
           let micStart = micTicksStartedAt, now.timeIntervalSince(micStart) > 4,
           sessionPeakLevel < 0.03 {
            silenceHintShown = true
            statusMessage = "No sound from the mic — close any app using it (or Bluetooth), then retry."
            FBLog.log("silence guard: no audio after 4s (peak \(sessionPeakLevel))")
        }
        let remaining = FlowBridgeConstants.maxRecordingSeconds - Date().timeIntervalSince(startedAt)
        let snapshot = LiveTranscriptStore.latest()
        let isCurrentSession = snapshot?.isRecording == true && snapshot?.sessionID == currentSessionID
        let liveText = isCurrentSession ? (snapshot?.text ?? "") : ""
        let contentState = DictationActivityAttributes.ContentState(
            phase: .recording,
            transcriptPreview: liveText,
            startedAt: startedAt,
            levels: AudioLevelMeter.shared.barSnapshot(),
            // Live word ticker: only changes when the text changes, which is
            // already an update trigger — the change gate stays intact. At
            // ready, numericText rolls from this to the polished count: you
            // watch the polish trim the fillers.
            wordCount: liveText.isEmpty ? nil : liveText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
            capWarning: remaining <= 60,
            engineBadge: currentEngineBadge,
            assistantMode: voiceMode == .act
        )
        guard contentState != lastSentIslandState else { return }
        lastSentIslandState = contentState
        activityController.update(contentState)
    }

    private func stopRecordingAndTranscribe() async {
        // The audio session releases at stop, and with it the background
        // assertion that was keeping the app alive — but decode + final pass
        // still have seconds of work left. Without this task, backgrounding
        // the app mid-transcribe suspends it and the dictation is lost
        // (observed on device: bundled cold load + home swipe = frozen
        // "transcribing" and no delivery).
        let backgroundLease = BackgroundExecutionLease()
        backgroundLease.identifier = UIApplication.shared.beginBackgroundTask(withName: "FlowBridge.finalPass") {
            FBLog.log("stop: background time expired during final pass")
            backgroundLease.end()
        }
        defer { backgroundLease.end() }

        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        stopIslandTick()
        recordingFeedback.stop()
        recordingElapsed = nil
        HapticPlayer.listeningStopped()

        // A stop while paused: fold the pause out of the timeline so
        // duration == recorded audio (stats, final-pass cap, island summary).
        if let pausedSince = pausedAt, case .recording(let pausedStart) = state {
            let recorded = pausedSince.timeIntervalSince(pausedStart)
            state = .recording(startedAt: Date().addingTimeInterval(-recorded))
            pausedAt = nil
            pauseKeepaliveTask?.cancel()
            pauseKeepaliveTask = nil
            pauseAutoStopTask?.cancel()
            pauseAutoStopTask = nil
        }

        let recordingStartedAt: Date
        if case .recording(let startedAt) = state {
            recordingStartedAt = startedAt
        } else {
            recordingStartedAt = Date()
        }
        // Captured before delivery clears it: the final pass needs it to
        // find the session's safety WAV.
        let sessionID = currentSessionID

        do {
            let duration = Date().timeIntervalSince(recordingStartedAt)
            FBLog.log("stop: transcribing after \(Int(duration))s")
            state = .transcribing
            processingStage = .finalizingAudio
            // Freeze the wave at its last real levels while the widget
            // narrates the polish phase.
            activityController.update(
                DictationActivityAttributes.ContentState(
                    phase: .transcribing,
                    transcriptPreview: LiveTranscriptStore.latest()?.text ?? "",
                    startedAt: recordingStartedAt,
                    levels: AudioLevelMeter.shared.barSnapshot(),
                    recordedSeconds: Int(duration.rounded()),
                    engineBadge: currentEngineBadge,
                    assistantMode: voiceMode == .act
                )
            )

            processingStage = .decodingSpeech
            var record = try await stopLiveTranscriptionAndReleaseEngine(duration: duration)
            FBLog.log("stop: engine returned \(record.text.count)ch")

            if let sessionID {
                processingStage = .refiningText
                statusMessage = FinalPassMode.current == .cloudScribe ? "Refining in cloud…" : "Refining…"
                // The island narrates the second micro-stage: REFINING (+☁).
                activityController.update(
                    DictationActivityAttributes.ContentState(
                        phase: .transcribing,
                        transcriptPreview: record.text,
                        startedAt: recordingStartedAt,
                        levels: AudioLevelMeter.shared.barSnapshot(),
                        recordedSeconds: Int(duration.rounded()),
                        engineBadge: finalPassBadge,
                        refining: true,
                        assistantMode: voiceMode == .act
                    )
                )
                let refined = await finalPass.refine(
                    sessionID: sessionID,
                    duration: duration,
                    fallback: record.text,
                    forceLocalRefinement: activeEnginePreference == .whisperPrecision
                )
                if refined != record.text {
                    record = TranscriptRecord(
                        text: refined,
                        language: record.language,
                        audioDuration: record.audioDuration,
                        source: record.source
                    )
                }
            }

            try await deliver(record, duration: duration, startedAt: recordingStartedAt)
        } catch {
            let duration = Date().timeIntervalSince(recordingStartedAt)

            // The stream heard nothing usable — but the full session audio
            // may still be rescued by the final pass (precision or cloud).
            if case FlowBridgeError.emptyTranscript = error, let sessionID {
                processingStage = .decodingSpeech
                statusMessage = "Recovering audio…"
                let rescued = await finalPass.refine(
                    sessionID: sessionID,
                    duration: duration,
                    fallback: "",
                    forceLocalRefinement: activeEnginePreference == .whisperPrecision
                )
                if !rescued.isEmpty {
                    FBLog.log("stop: rescued \(rescued.count)ch via final pass")
                    let record = TranscriptRecord(
                        text: rescued,
                        language: DictationLanguage.current.whisperCode ?? "und",
                        audioDuration: duration,
                        source: .microphone
                    )
                    if (try? await deliver(record, duration: duration, startedAt: recordingStartedAt)) != nil {
                        return
                    }
                }
            }

            liveTranscript = nil
            currentSessionID = nil
            activityController.finish(
                transcriptPreview: Self.errorMessage(for: error),
                startedAt: recordingStartedAt,
                failed: true
            )
            fail(error)
        }
    }

    /// Stops hardware and then releases the live recognizer on both success
    /// and failure. The next stage may load diarization, a precision pass, or
    /// Foundation Models; none may overlap the live model in memory.
    private func stopLiveTranscriptionAndReleaseEngine(duration: TimeInterval) async throws -> TranscriptRecord {
        let engine = transcriber
        do {
            let record = try await engine.stopLiveTranscription(duration: duration)
            await engine.unload()
            FBLog.log("stop: live model released before refinement")
            return record
        } catch {
            await engine.unload()
            FBLog.log("stop: live model released after decode failure")
            throw error
        }
    }

    /// Everything between "we have the take's text" and "the user has it":
    /// deterministic spoken commands, history, stats, session append,
    /// clipboard, island summary, haptics.
    ///
    /// Foundation Models deliberately does not run on this critical path.
    /// iOS may suspend an app immediately after a background stop; waiting
    /// for optional generative cleanup here could strand a valid transcript
    /// in the transcribing state. The verbatim take is delivered first and
    /// refinement remains an explicit, reversible post-delivery action.
    private func deliver(_ record: TranscriptRecord, duration: TimeInterval, startedAt recordingStartedAt: Date) async throws {
        // Spoken commands ("punto", "a capo", …) are deterministic and
        // safe to apply synchronously. Labeled multi-speaker transcripts are
        // left verbatim so their structure cannot be altered accidentally.
        var workingText = record.text
        if SpeakerTranscriptFormatter.turns(in: workingText) == nil,
           Self.voiceCommandsEnabled {
            workingText = VoiceCommandProcessor.apply(to: workingText)
        }
        let finalRecord = workingText == record.text ? record : record.polished(workingText)

        processingStage = .delivering
        try? await historyStore?.add(finalRecord)
        let outcome = statsStore?.record(text: finalRecord.text, audioDuration: duration)

        let delivered = sessionAppendedRecord(for: finalRecord) ?? finalRecord
        try await transcriptStore?.save(delivered)
        WidgetCenter.shared.reloadAllTimelines()
        lastTranscript = delivered
        liveTranscript = nil
        currentSessionID = nil
        // The reveal narrates this take (pre-append): a merged record
        // has no rawText of its own.
        polishReveal = PolishReveal(record: finalRecord)
        UIPasteboard.general.string = delivered.text
        processingStage = nil
        state = .ready
        statusMessage = delivered.id == finalRecord.id ? "Clipboard updated" : "Appended to previous dictation"
        FBLog.log("delivery: ready (\(finalRecord.text.count)ch); refinement is optional")
        // The island summary describes the take just recorded — with
        // session append, the merged word count would contradict the
        // recorded seconds.
        let refinementAvailable = await polisher.isEnabled
        activityController.deliverInteractive(
            transcriptPreview: delivered.text,
            startedAt: recordingStartedAt,
            wordCount: finalRecord.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
            recordedSeconds: Int(duration.rounded()),
            variantsAvailable: refinementAvailable,
            assistantMode: voiceMode == .act
        )
        if let outcome {
            streakDays = outcome.streakDays
            isNewStreakDay = outcome.isNewStreakDay
        }
        timeSavedMinutes = statsStore?.stats().timeSavedMinutes ?? timeSavedMinutes
        vocabularySuggestions = VocabularySuggester.suggestions(from: finalRecord.rawText ?? finalRecord.text)
        HapticPlayer.transcriptReady()

        // Keep the individual take (not the session-appended merge) ready for
        // Act mode. Dictate mode stops here and never loads the assistant.
        lastActionCandidateText = finalRecord.text
        suggestionRecordID = finalRecord.id
        if voiceMode == .act {
            scheduleActionDiscovery(text: finalRecord.text, recordID: finalRecord.id)
        }
    }

    /// Intent detection rides strictly after delivery: the text is already
    /// on the clipboard and in History whatever the optional model does.
    private func scheduleActionDiscovery(text: String, recordID: UUID) {
        guard voiceMode == .act else { return }
        suggestedAction = nil
        suggestionTask?.cancel()
        suggestionTask = Task { [weak self] in
            let suggestion = await IntentClassifier.shared.classify(text)
            guard !Task.isCancelled,
                  let self,
                  self.voiceMode == .act,
                  self.suggestionRecordID == recordID,
                  let suggestion else { return }
            FBLog.log("actions: suggesting \(suggestion.label)")
            self.suggestedAction = suggestion
            self.activityController.offerSuggestedAction(
                kind: suggestion.activityKind,
                title: suggestion.activityTitle,
                detail: suggestion.detail
            )
        }
    }

    func performSuggestedAction() async {
        guard let action = suggestedAction, let recordID = suggestionRecordID else { return }
        let outcome = await ActionPerformer.shared.perform(action)
        // `perform` can suspend for a while (EventKit permission round-trip,
        // composer hand-off) — a newer take may have already delivered and
        // replaced the suggestion in that window. Don't let this stale
        // outcome stamp the wrong History record or clear the new chip.
        guard suggestionRecordID == recordID else { return }
        suggestedAction = nil
        switch outcome {
        case .done(let message):
            HapticPlayer.transcriptReady()
            actionConfirmation = message
            activityController.noteActionCompleted(message)
            // The Flow trail: History shows what this dictation became.
            try? await historyStore?.setAction(message, id: recordID)
            confirmationDismissTask?.cancel()
            confirmationDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.actionConfirmation = nil
            }
        case .openedApp:
            activityController.noteActionCompleted(action.handoffHistoryLabel)
            try? await historyStore?.setAction(action.handoffHistoryLabel, id: recordID)
        case .failed(let message):
            statusMessage = message
            activityController.noteActionFailed()
        }
    }

    func dismissSuggestedAction() {
        suggestedAction = nil
        activityController.clearSuggestedAction()
    }

    func addVocabularySuggestion(_ term: String) {
        if let store = try? VocabularyStore() {
            try? store.add(term)
        }
        vocabularySuggestions.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        HapticPlayer.transcriptReady()
    }

    func dismissVocabularySuggestion(_ term: String) {
        VocabularySuggester.dismiss(term)
        vocabularySuggestions.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    private static var voiceCommandsEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.voiceCommandsEnabledKey) as? Bool ?? true
    }

    private static var sessionAppendWindow: TimeInterval {
        let defaults = try? SharedContainer.userDefaults()
        guard let value = defaults?.object(forKey: FlowBridgeConstants.sessionAppendWindowKey) as? Double else {
            return FlowBridgeConstants.sessionAppendWindowDefault
        }
        return value
    }

    /// Session append: a dictation finished shortly after the previous one
    /// continues it — the delivered transcript (clipboard/keyboard) is the
    /// merge, while history keeps the individual takes.
    private func sessionAppendedRecord(for record: TranscriptRecord) -> TranscriptRecord? {
        let window = Self.sessionAppendWindow
        guard window > 0,
              let last = lastTranscript,
              last.source == .microphone || last.source == .recovered,
              record.createdAt.timeIntervalSince(last.createdAt) <= window else {
            return nil
        }

        return TranscriptRecord(
            text: last.text + " " + record.text,
            language: record.language,
            audioDuration: last.audioDuration + record.audioDuration,
            source: .microphone
        )
    }

    private func processQueuedAudioIfNeeded() async {
        guard let url = QueuedAudioStore.latestQueuedAudioURL() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            try? QueuedAudioStore.clear(removeFile: false)
            fail(FlowBridgeError.queuedAudioMissing)
            return
        }

        state = .transcribing
        statusMessage = url.lastPathComponent

        do {
            let duration = await AudioFileDurationReader.duration(of: url) ?? 0
            let recording = RecordedAudio(url: url, duration: duration)
            let engine = await resolveEngine()
            let record = try await engine.transcribe(recording: recording, source: .sharedAudio)
            try await transcriptStore?.save(record)
            try? QueuedAudioStore.clear(removeFile: true)
            lastTranscript = record
            UIPasteboard.general.string = record.text
            state = .ready
            statusMessage = "Clipboard updated"
        } catch {
            fail(error)
        }
    }

    private func recoverInterruptedDictationIfNeeded() async {
        guard case .idle = state else { return }
        guard let directory = try? AudioSafetyBuffer.defaultDirectory() else { return }

        let pending = AudioSafetyBuffer.pendingRecordings(in: directory)
        guard !pending.isEmpty else { return }

        for recording in pending {
            guard recording.duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds else {
                AudioSafetyBuffer.remove(recording)
                InterruptedRecoveryGuard.clear(recording.url)
                continue
            }

            // A SIGKILL cannot run cleanup. The durable sidecar means the
            // next launch offers a deliberate retry instead of loading the
            // same model forever and making the app appear unable to open.
            guard !InterruptedRecoveryGuard.hasAttempted(recording.url) else {
                presentInterruptedRecovery(
                    "Your interrupted recording is safe. Recover it when the phone has memory available."
                )
                return
            }

            do {
                try InterruptedRecoveryGuard.markAttempted(recording.url)
            } catch {
                FBLog.log("recovery: could not persist attempt guard (\(error))")
                presentInterruptedRecovery(
                    "Your interrupted recording is safe, but recovery could not start yet."
                )
                return
            }

            state = .transcribing
            statusMessage = "Recovering interrupted dictation"
            FBLog.log("recovery: bundled safe pass for \(recording.url.lastPathComponent)")

            // Never recover with the user's Precision streaming preference.
            // The bundled model is the known-good, lower-peak rescue path.
            let recoveryEngine = WhisperEngine(variant: .bundled)

            do {
                let audio = RecordedAudio(url: recording.url, duration: recording.duration)
                let record = try await recoveryEngine.transcribe(recording: audio, source: .recovered)
                await recoveryEngine.unload()
                try await transcriptStore?.save(record)
                lastTranscript = record
                UIPasteboard.general.string = record.text
                state = .ready
                statusMessage = "Recovered interrupted dictation"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                await recoveryEngine.unload()
                FBLog.log("recovery FAILED, audio retained: \(error)")
                presentInterruptedRecovery(
                    "The first recovery attempt did not finish. Your audio is still safe; tap to try again."
                )
                return
            }

            AudioSafetyBuffer.remove(recording)
            InterruptedRecoveryGuard.clear(recording.url)
        }
    }

    /// Explicit retry from the recovery card. Clearing the marker is a user
    /// decision; the recovery method immediately recreates it before loading
    /// a model, so another system kill still cannot create a boot loop.
    func retryInterruptedDictation() async {
        guard let directory = try? AudioSafetyBuffer.defaultDirectory() else { return }
        for recording in AudioSafetyBuffer.pendingRecordings(in: directory) {
            InterruptedRecoveryGuard.clear(recording.url)
        }
        errorPresentation = nil
        statusMessage = nil
        state = .idle
        await recoverInterruptedDictationIfNeeded()
    }

    private func presentInterruptedRecovery(_ message: String) {
        let title = "Recording kept safe"
        state = .failed(message)
        statusMessage = nil
        errorPresentation = FlowErrorPresentation(
            title: title,
            message: message,
            symbol: "waveform.badge.exclamationmark",
            recovery: .recoverInterrupted
        )
    }

    private func stopIfRecording() async {
        if case .recording = state {
            await stopRecordingAndTranscribe()
        }
    }

    // MARK: - Pause / resume

    private var pauseKeepaliveTask: Task<Void, Never>?
    private var pauseAutoStopTask: Task<Void, Never>?

    private var currentEngineBadge: DictationActivityAttributes.ContentState.EngineBadge {
        activeEnginePreference == .cloudRealtime ? .cloud : .local
    }

    private var finalPassBadge: DictationActivityAttributes.ContentState.EngineBadge? {
        if activeEnginePreference == .whisperPrecision {
            return .local
        }
        switch FinalPassMode.current {
        case .off: return nil
        case .localPrecision: return .local
        case .cloudScribe: return CloudCredentialsStore.hasKey ? .cloud : .local
        }
    }

    func pauseDictation() async {
        guard case .recording(let startedAt) = state, pausedAt == nil else { return }
        // Cloud realtime can't pause cleanly (socket idle/billing): the
        // island hides the button; this guard covers every other path.
        guard currentEngineBadge == .local else { return }

        FBLog.log("pause: engaging")
        await transcriber.pauseLive()
        pausedAt = Date()
        // Risk #1/#2 fixes: both timers stop; resume restarts them with the
        // REMAINING budget, so the cap can never fire mid-pause.
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        stopIslandTick()
        recordingFeedback.stop()
        statusMessage = "Paused"
        pushPausedIslandState(startedAt: startedAt)
        startPauseKeepalive(startedAt: startedAt)
        startPauseAutoStop()
    }

    func resumeDictation() async {
        guard case .recording(let oldStartedAt) = state, let pausedSince = pausedAt else { return }
        FBLog.log("pause: resuming")
        pauseKeepaliveTask?.cancel()
        pauseKeepaliveTask = nil
        pauseAutoStopTask?.cancel()
        pauseAutoStopTask = nil

        do {
            try await transcriber.resumeLive()
        } catch {
            FBLog.log("pause: resume failed (\(error)) — stopping instead")
            pausedAt = nil
            await stopRecordingAndTranscribe()
            return
        }

        // Shift the session origin by the pause: elapsed == recorded audio,
        // and the in-widget cap math (startedAt + max) stays truthful.
        let pauseDuration = Date().timeIntervalSince(pausedSince)
        let newStartedAt = oldStartedAt.addingTimeInterval(pauseDuration)
        let recordedSoFar = pausedSince.timeIntervalSince(oldStartedAt)
        pausedAt = nil
        state = .recording(startedAt: newStartedAt)
        statusMessage = "Live bridge active"
        startElapsedTimer(from: newStartedAt)
        startMaxDurationTimer(remaining: max(5, FlowBridgeConstants.maxRecordingSeconds - recordedSoFar))
        startIslandTick(startedAt: newStartedAt)
        recordingFeedback.start()
    }

    private func pushPausedIslandState(startedAt: Date) {
        let contentState = DictationActivityAttributes.ContentState(
            phase: .recording,
            transcriptPreview: liveTranscript?.text ?? "",
            startedAt: startedAt,
            levels: DictationActivityAttributes.ContentState.restingLevels,
            engineBadge: currentEngineBadge,
            assistantMode: voiceMode == .act,
            pausedAt: pausedAt
        )
        lastSentIslandState = contentState
        activityController.update(contentState)
    }

    /// Paused = no state changes = no updates: without a keepalive the
    /// island would go stale and show the recovery copy while legitimately
    /// paused. Bounded, user-initiated cost: ~2 updates/min.
    private func startPauseKeepalive(startedAt: Date) {
        pauseKeepaliveTask?.cancel()
        pauseKeepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.pushPausedIslandState(startedAt: startedAt)
            }
        }
    }

    /// A backgrounded app with a gated mic can be suspended: cap the pause
    /// so a forgotten session still delivers its words.
    private func startPauseAutoStop() {
        pauseAutoStopTask?.cancel()
        pauseAutoStopTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            FBLog.log("pause: 5min cap reached — auto-stopping")
            await self?.stopIfRecording()
        }
    }

    // MARK: - Tone variants (island ready-window)

    func applyToneVariant(_ rawTone: String) async {
        guard let tone = ToneProfile(rawValue: rawTone),
              let base = lastTranscript?.text,
              !base.isEmpty else { return }
        FBLog.log("variant: \(rawTone)")
        let variantWork = Task { [polisher] in
            if let turns = SpeakerTranscriptFormatter.turns(in: base) {
                // Labeled conversation: per-turn, same rule as delivery.
                guard turns.count <= FlowBridgeConstants.speakerPolishMaxTurns else { return base }
                var polished: [SpeakerTranscriptFormatter.Turn] = []
                for turn in turns {
                    guard !Task.isCancelled else { return base }
                    polished.append(.init(
                        label: turn.label,
                        text: await polisher.polish(turn.text, tone: tone)
                    ))
                }
                return SpeakerTranscriptFormatter.compose(turns: polished)
            }
            return await polisher.polish(base, tone: tone)
        }
        let outcome = await TaskDeadline.value(
            from: variantWork,
            fallback: base,
            after: .seconds(8)
        )
        let variant = outcome.value
        UIPasteboard.general.string = variant
        let variantName = tone == .neutral ? "Refined" : tone.displayName
        statusMessage = outcome.timedOut ? "Verbatim copied — refine took too long" : "\(variantName) copied"
        HapticPlayer.transcriptReady()
        activityController.noteVariantApplied(
            outcome.timedOut ? "Verbatim copied ✓" : "\(variantName) copied ✓",
            preview: variant
        )
    }

    private func handleMemoryWarning() async {
        FBLog.log("memory warning, state=\(state)")
        let pendingSuggestion = suggestionTask
        suggestionTask = nil
        await TaskQuiescer.cancelAndWait(pendingSuggestion)
        await IntentClassifier.shared.releaseSession()
        await polisher.releaseSession()
        switch state {
        case .idle, .ready, .failed:
            await transcriber.unload()
        case .warming, .recording, .transcribing:
            // Never tear down the model that owns an active operation. The
            // optional language-model work above is safe to cancel; the core
            // recognizer is released at the explicit stage handoff.
            break
        }
    }

    private func startElapsedTimer(from startDate: Date) {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.recordingElapsed = Date().timeIntervalSince(startDate)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func startMaxDurationTimer(remaining: TimeInterval = FlowBridgeConstants.maxRecordingSeconds) {
        maxDurationTask?.cancel()
        maxDurationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return // cancelled (pause, stop): never fall through
            }
            guard !Task.isCancelled else { return }
            await self?.stopIfRecording()
        }
    }

    private func fail(_ error: Error) {
        FBLog.log("fail: \(error)")
        // A stop that raced an already-ended session is a shrug, not a
        // failure: reset quietly instead of alarming the user.
        if case FlowBridgeError.notRecording = error {
            processingStage = nil
            state = .idle
            statusMessage = nil
            return
        }
        let message = Self.errorMessage(for: error)
        processingStage = nil
        state = .failed(message)
        // statusCaption hides itself whenever errorPresentation is set (see
        // ContentView), so that's the only channel the failure card reads —
        // no separate statusMessage write to keep in sync with it.
        errorPresentation = Self.presentation(for: error)
        HapticPlayer.failed()
    }

    func dismissError() {
        errorPresentation = nil
        if case .failed = state {
            state = .idle
            statusMessage = nil
        }
    }

    // `message` always comes from `errorMessage(for:)` — the one place
    // error copy is written, also used by the Live Activity narration — so
    // the in-app card and the island can never drift into saying two
    // different things about the same failure.
    private static func presentation(for error: Error) -> FlowErrorPresentation {
        switch error {
        case FlowBridgeError.microphonePermissionDenied:
            return FlowErrorPresentation(
                title: "Microphone is off",
                message: errorMessage(for: error),
                symbol: "mic.slash",
                recovery: .openSettings
            )
        case FlowBridgeError.emptyTranscript:
            return FlowErrorPresentation(
                title: "Nothing heard",
                message: errorMessage(for: error),
                symbol: "waveform.slash",
                recovery: .tryAgain
            )
        case FlowBridgeError.modelMissing:
            return FlowErrorPresentation(
                title: "Model missing",
                message: errorMessage(for: error),
                symbol: "square.stack.3d.up.slash",
                recovery: nil
            )
        default:
            return FlowErrorPresentation(
                title: "That didn't work",
                message: errorMessage(for: error),
                symbol: "exclamationmark.triangle",
                recovery: .tryAgain
            )
        }
    }

    private static func errorMessage(for error: Error) -> String {
        if case FlowBridgeError.emptyTranscript = error {
            // The most common "nothing heard" cause is a mic the app never
            // truly got (another recorder, a call, silent Bluetooth). Say
            // what to do, not just what happened.
            return "No sound picked up — close any app using the mic (or Bluetooth), then try again."
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

@MainActor
private final class BackgroundExecutionLease {
    var identifier: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
