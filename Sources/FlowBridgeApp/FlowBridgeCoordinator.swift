import FlowBridgeShared
import SwiftUI
import UIKit

@MainActor
final class FlowBridgeCoordinator: ObservableObject {
    /// Single instance shared by the SwiftUI scene and by App Intents, which
    /// the system executes in this same process (AudioRecordingIntent /
    /// LiveActivityIntent) and which must reach the live audio session.
    static let shared = FlowBridgeCoordinator()

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
    @Published private(set) var lastTranscript: TranscriptRecord?
    @Published private(set) var statusMessage: String?
    @Published private(set) var recordingElapsed: TimeInterval?
    /// Live words as they stream in, for the in-app transcript view.
    @Published private(set) var liveTranscript: LiveTranscriptSnapshot?
    /// Set when a finished take was visibly improved by the polisher.
    @Published private(set) var polishReveal: PolishReveal?
    /// "Time given back" total, refreshed after every session (the ticker
    /// under the Orb counts up to it).
    @Published private(set) var timeSavedMinutes: Double = 0
    /// Consecutive dictation days, and whether the last session opened a
    /// new day (drives the streak celebration).
    @Published private(set) var streakDays: Int = 0
    @Published private(set) var isNewStreakDay: Bool = false

    private let recorder = FlowBridgeRecorder()
    private let transcriber: any TranscriptionEngine = EngineFactory.makeCurrent()
    private let activityController = DictationActivityController()
    private let polisher = TranscriptPolisher.shared
    private let recordingFeedback = RecordingFeedbackDriver()
    private var transcriptStore: TranscriptStore?
    private var historyStore: TranscriptHistoryStore?
    private var statsStore: DictationStatsStore?
    private var toneStore: ToneContextStore?
    private var pendingCommandStore: PendingCommandStore?
    private var elapsedTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var islandTask: Task<Void, Never>?
    private var lastSentIslandState: DictationActivityAttributes.ContentState?
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
        if case .recording = state { return }
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

    func consumePendingCommand() async {
        guard let command = pendingCommandStore?.consume()?.command else { return }
        FBLog.log("pending command consumed: \(command)")

        switch command {
        case .toggleRecording:
            await toggleRecording()
        case .stopRecording:
            await stopIfRecording()
        case .transcribeQueuedAudio:
            await processQueuedAudioIfNeeded()
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

    func copyLastTranscript() async {
        guard let text = lastTranscript?.text else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func unloadModel() async {
        await transcriber.unload()
        statusMessage = "Model unloaded"
    }

    private func startRecording(requestPermission: Bool = true) async {
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
            currentSessionID = sessionID
            lastSeenSnapshotSequence = 0
            AudioLevelMeter.shared.reset()
            HapticPlayer.prepare()
            // The Live Activity goes up before the engine warms: the island
            // responds to the trigger instantly, and background starts via
            // AudioRecordingIntent require a visible activity to keep audio.
            activityController.start(sessionID: sessionID, startedAt: startedAt)
            FBLog.log("start: warming, engine=\(type(of: transcriber)) session=\(sessionID.uuidString.prefix(8))")
            try await transcriber.startLiveTranscription(sessionID: sessionID)
            FBLog.log("start: recording")
            state = .recording(startedAt: startedAt)
            statusMessage = "Live bridge active"
            startElapsedTimer(from: startedAt)
            startMaxDurationTimer()
            startIslandTick(startedAt: startedAt)
            recordingFeedback.start()
            HapticPlayer.listeningStarted()
            // Prewarm off the session-start memory peak: the polisher LLM
            // and the just-loaded Whisper model shouldn't spike together.
            Task {
                try? await Task.sleep(for: .seconds(3))
                await polisher.prewarm()
            }
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
        let remaining = FlowBridgeConstants.maxRecordingSeconds - Date().timeIntervalSince(startedAt)
        let snapshot = LiveTranscriptStore.latest()
        let isCurrentSession = snapshot?.isRecording == true && snapshot?.sessionID == currentSessionID
        let contentState = DictationActivityAttributes.ContentState(
            phase: .recording,
            transcriptPreview: isCurrentSession ? (snapshot?.text ?? "") : "",
            startedAt: startedAt,
            levels: AudioLevelMeter.shared.barSnapshot(),
            capWarning: remaining <= 60
        )
        guard contentState != lastSentIslandState else { return }
        lastSentIslandState = contentState
        activityController.update(contentState)
    }

    private func stopRecordingAndTranscribe() async {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        stopIslandTick()
        recordingFeedback.stop()
        recordingElapsed = nil
        HapticPlayer.listeningStopped()

        let recordingStartedAt: Date
        if case .recording(let startedAt) = state {
            recordingStartedAt = startedAt
        } else {
            recordingStartedAt = Date()
        }

        do {
            let duration = Date().timeIntervalSince(recordingStartedAt)
            FBLog.log("stop: transcribing after \(Int(duration))s")
            state = .transcribing
            // Freeze the wave at its last real levels while the widget
            // narrates the polish phase.
            activityController.update(
                DictationActivityAttributes.ContentState(
                    phase: .transcribing,
                    transcriptPreview: LiveTranscriptStore.latest()?.text ?? "",
                    startedAt: recordingStartedAt,
                    levels: AudioLevelMeter.shared.barSnapshot(),
                    recordedSeconds: Int(duration.rounded())
                )
            )

            let record = try await transcriber.stopLiveTranscription(duration: duration)
            FBLog.log("stop: engine returned \(record.text.count)ch")

            // Deterministic spoken commands first ("punto", "a capo", …),
            // then the on-device polish with the current tone target. The
            // engine's verbatim text always survives in rawText.
            var workingText = record.text
            if Self.voiceCommandsEnabled {
                workingText = VoiceCommandProcessor.apply(to: workingText)
            }
            let tone = toneStore?.currentTone() ?? .neutral
            workingText = await polisher.polish(workingText, tone: tone)
            let finalRecord = workingText == record.text ? record : record.polished(workingText)

            try? await historyStore?.add(finalRecord)
            let outcome = statsStore?.record(text: finalRecord.text, audioDuration: duration)

            let delivered = sessionAppendedRecord(for: finalRecord) ?? finalRecord
            try await transcriptStore?.save(delivered)
            lastTranscript = delivered
            liveTranscript = nil
            currentSessionID = nil
            // The reveal narrates this take (pre-append): a merged record
            // has no rawText of its own.
            polishReveal = PolishReveal(record: finalRecord)
            UIPasteboard.general.string = delivered.text
            state = .ready
            statusMessage = delivered.id == finalRecord.id ? "Clipboard updated" : "Appended to previous dictation"
            // The island summary describes the take just recorded — with
            // session append, the merged word count would contradict the
            // recorded seconds.
            activityController.finish(
                transcriptPreview: delivered.text,
                startedAt: recordingStartedAt,
                wordCount: finalRecord.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
                recordedSeconds: Int(duration.rounded())
            )
            if let outcome {
                streakDays = outcome.streakDays
                isNewStreakDay = outcome.isNewStreakDay
            }
            timeSavedMinutes = statsStore?.stats().timeSavedMinutes ?? timeSavedMinutes
            HapticPlayer.transcriptReady()
        } catch {
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
            let duration = AudioFileDurationReader.duration(of: url) ?? 0
            let recording = RecordedAudio(url: url, duration: duration)
            let record = try await transcriber.transcribe(recording: recording, source: .sharedAudio)
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
                continue
            }

            state = .transcribing
            statusMessage = "Recovering interrupted dictation"

            do {
                let audio = RecordedAudio(url: recording.url, duration: recording.duration)
                let record = try await transcriber.transcribe(recording: audio, source: .recovered)
                try await transcriptStore?.save(record)
                lastTranscript = record
                UIPasteboard.general.string = record.text
                state = .ready
                statusMessage = "Recovered interrupted dictation"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                state = .idle
                statusMessage = "Interrupted dictation could not be recovered"
            }

            AudioSafetyBuffer.remove(recording)
        }
    }

    private func stopIfRecording() async {
        if case .recording = state {
            await stopRecordingAndTranscribe()
        }
    }

    private func handleMemoryWarning() async {
        FBLog.log("memory warning, state=\(state)")
        switch state {
        case .idle, .ready, .failed:
            await transcriber.unload()
        case .warming, .recording, .transcribing:
            // Loading the model spikes memory exactly here, so iOS often
            // warns mid-start. Unloading now would kill the session we just
            // opened (the V1 bug): keep it — the OS reclaims by force if it
            // truly must.
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

    private func startMaxDurationTimer() {
        maxDurationTask?.cancel()
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FlowBridgeConstants.maxRecordingSeconds))
            await self?.stopIfRecording()
        }
    }

    private func fail(_ error: Error) {
        FBLog.log("fail: \(error)")
        // A stop that raced an already-ended session is a shrug, not a
        // failure: reset quietly instead of alarming the user.
        if case FlowBridgeError.notRecording = error {
            state = .idle
            statusMessage = nil
            return
        }
        let message = Self.errorMessage(for: error)
        state = .failed(message)
        statusMessage = message
        HapticPlayer.failed()
    }

    private static func errorMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
