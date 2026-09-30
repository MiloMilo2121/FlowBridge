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

    @Published private(set) var state: State = .idle
    @Published private(set) var lastTranscript: TranscriptRecord?
    @Published private(set) var statusMessage: String?
    @Published private(set) var recordingElapsed: TimeInterval?
    /// Safety-buffer recordings automatic recovery gave up on; listed in
    /// Settings so the audio is never stranded on disk.
    @Published private(set) var unrecoveredDictations: [AudioSafetyBuffer.PendingRecording] = []

    // Starts as the bundled default; bootstrap swaps in the configured
    // engine (the factory is async: the Apple engine's locale check is).
    private var transcriber: any TranscriptionEngine = WhisperEngine()
    private var enginePreference = EnginePreference.whisper
    private let activityController = DictationActivityController()
    private let polisher = TranscriptPolisher.shared
    private var transcriptStore: TranscriptStore?
    private var historyStore: TranscriptHistoryStore?
    private var statsStore: DictationStatsStore?
    private var toneStore: ToneContextStore?
    private var pendingCommandStore: PendingCommandStore?
    private var elapsedTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?
    private var commandObserver: DarwinNotificationObserver?
    private var liveSnapshotObserver: DarwinNotificationObserver?
    private var lastActivityPreview = ""
    private var lastActivityPushAt = Date.distantPast
    /// Identifies the warm-up in flight; cleared by abortWarmup so a start
    /// that completes after the user cancelled tears itself down instead of
    /// resurrecting the session.
    private var warmupToken: UUID?

    init() {
        // Handlers go in here, not in `bootstrap()`: an intent can be the
        // very first code to run in this process, and a start request that
        // finds no handler throws, which opens the app instead of just
        // dictating. `AppDelegate` touches `.shared` at launch so this runs
        // before any intent can.
        registerCommandHub()

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

    deinit {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func bootstrap() async {
        transcriptStore = try? TranscriptStore()
        historyStore = try? TranscriptHistoryStore()
        statsStore = try? DictationStatsStore()
        toneStore = try? ToneContextStore()
        pendingCommandStore = try? PendingCommandStore()
        lastTranscript = transcriptStore?.latest()
        await refreshEngineIfNeeded(force: true)
        await recoverInterruptedDictationIfNeeded()
        // Observers come up only after recovery so a user trigger that fires
        // mid-recovery is deferred (see consumePendingCommand), not raced.
        registerObservers()
        await consumePendingCommand()
        await processQueuedAudioIfNeeded()
    }

    /// Wires App Intents to this coordinator.
    private func registerCommandHub() {
        DictationCommandHub.shared.startHandler = { [weak self] in
            try await self?.startBackgroundDictation()
        }
        DictationCommandHub.shared.stopHandler = { [weak self] in
            await self?.stopIfRecording()
        }
        DictationCommandHub.shared.toggleHandler = { [weak self] in
            await self?.toggleRecording()
        }
    }

    private func registerObservers() {
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

        // Mirror live transcript snapshots into the Live Activity so the
        // Dynamic Island shows the words as they stream.
        liveSnapshotObserver = DarwinNotificationObserver(
            name: FlowBridgeConstants.liveTranscriptDidChangeDarwinName
        ) {
            Task { @MainActor in
                FlowBridgeCoordinator.shared.pushLiveSnapshotToActivity()
            }
        }
    }

    /// Start requested by `StartDictationIntent` while the app may be
    /// backgrounded: no permission prompt is possible there, and the Live
    /// Activity must be up for as long as the recording runs (the system
    /// stops background audio otherwise). Throws when the background path is
    /// not viable so the intent can fall back to opening the app.
    func startBackgroundDictation() async throws {
        switch state {
        case .recording, .warming:
            // Already started (or starting): the request is satisfied.
            return
        case .transcribing:
            // Finishing the previous dictation (or recovering one). Starting
            // now would overwrite that work's state mid-flight.
            throw FlowBridgeError.dictationBusy
        case .idle, .ready, .failed:
            break
        }
        guard MicrophonePermission.isGranted else {
            throw FlowBridgeError.microphonePermissionDenied
        }
        // Without a Live Activity the system stops background audio, so this
        // path is only viable if the activity can actually go up.
        guard activityController.isAvailable else {
            throw FlowBridgeError.liveActivityUnavailable
        }

        await startRecording(requestPermission: false, requiresActivity: true)

        guard case .recording = state else {
            throw FlowBridgeError.recorderFailed(statusMessage ?? "Background start failed.")
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await consumePendingCommand()
            await processQueuedAudioIfNeeded()
        case .background:
            switch state {
            case .recording:
                statusMessage = "Live bridge active"
            case .warming, .transcribing:
                // Work is in flight; unloading now would kill it. The idle
                // TTL reclaims the model memory afterwards.
                break
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
        if case .transcribing = state {
            // A toggle/stop that lands while the previous dictation is being
            // transcribed has already been satisfied: the recording stopped.
            // Replaying it afterwards would START a new dictation the user
            // never asked for, so drop it. Queued-audio work is real and
            // stays stored for the drain at the end of the transcription.
            if let stale = pendingCommandStore?.peek()?.command,
               stale == .toggleRecording || stale == .stopRecording {
                _ = pendingCommandStore?.consume()
            }
            return
        }

        guard let command = pendingCommandStore?.consume()?.command else { return }

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
        case .warming:
            await abortWarmup()
        case .transcribing:
            break
        case .idle, .ready, .failed:
            await startRecording()
        }
    }

    func requestMicrophonePermission() async -> Bool {
        await MicrophonePermission.request()
    }

    var history: TranscriptHistoryStore? { historyStore }
    var stats: DictationStatsStore? { statsStore }
    var toneContext: ToneContextStore? { toneStore }

    func copyLastTranscript() async {
        guard let text = lastTranscript?.text else { return }
        UIPasteboard.general.string = text
        HapticPlayer.transcriptReady()
    }

    func unloadModel() async {
        await transcriber.unload()
        statusMessage = "Model unloaded"
    }

    /// An engine change in Settings takes effect at the next dictation
    /// (never mid-session): unload the old engine and build the new one.
    private func refreshEngineIfNeeded(force: Bool = false) async {
        let preference = EnginePreference.current
        // Selection satisfied as-is: the common path costs nothing.
        guard force || preference != enginePreference else { return }
        // Either a new selection or a standing fallback. Resolve before
        // building: a fallback that still resolves to the engine already
        // loaded is not rebuilt on every dictation, and one whose cause
        // went away (key added, locale supported) is.
        let resolved = await EngineFactory.resolve(preference)
        guard force || resolved != enginePreference else { return }
        switch state {
        case .idle, .ready, .failed:
            await transcriber.unload()
            let built = EngineFactory.make(resolved)
            transcriber = built.engine
            // Record the engine we ACTUALLY got, not the one that was
            // asked for, so the status can tell the user which is running.
            enginePreference = built.resolved
            if built.resolved != preference, built.resolved == .whisper {
                // Only the downgrade is worth interrupting the user for:
                // silently dictating with a different engine than the one
                // selected is the kind of thing that reads as a bug.
                statusMessage = "\(preference.displayName) isn't available — using \(built.resolved.displayName)"
            }
        case .warming, .recording, .transcribing:
            break
        }
    }

    /// True when the engine in use is not the one the user selected, so the
    /// recording status can say why.
    private var engineFallbackNote: String? {
        let selected = EnginePreference.current
        guard selected != enginePreference, enginePreference == .whisper else { return nil }
        return "\(selected.displayName) isn't available — using \(enginePreference.displayName)"
    }

    /// - Parameter requiresActivity: background starts only. Without a
    ///   visible Live Activity the system tears the audio down, so a refused
    ///   activity request fails the start before the engine warms.
    private func startRecording(requestPermission: Bool = true, requiresActivity: Bool = false) async {
        // Only a settled coordinator may start: during warm-up, recording or
        // transcription (including recovery) a start would overwrite the
        // state of the work in flight.
        switch state {
        case .idle, .ready, .failed:
            break
        case .warming, .recording, .transcribing:
            return
        }
        await refreshEngineIfNeeded()
        let startedAt = Date()
        let sessionID = UUID()
        var warmupStarted = false
        do {
            if requestPermission {
                guard await MicrophonePermission.request() else {
                    throw FlowBridgeError.microphonePermissionDenied
                }
            } else {
                guard MicrophonePermission.isGranted else {
                    throw FlowBridgeError.microphonePermissionDenied
                }
            }

            state = .warming
            statusMessage = "Loading local engine"
            lastActivityPreview = ""
            lastActivityPushAt = .distantPast
            warmupToken = sessionID
            warmupStarted = true
            // The Live Activity goes up before the engine warms: the island
            // responds to the trigger instantly, and background starts via
            // AudioRecordingIntent require a visible activity to keep audio.
            // Foreground dictation works without one, so a refusal here is
            // only fatal on the background path.
            let activityStarted = activityController.start(sessionID: sessionID, startedAt: startedAt)
            if requiresActivity, !activityStarted {
                throw FlowBridgeError.liveActivityUnavailable
            }
            try await startLiveWithWarmupDeadline(sessionID: sessionID)

            // The user may have cancelled while we were warming.
            guard warmupToken == sessionID else {
                await transcriber.unload()
                return
            }
            warmupToken = nil
            state = .recording(startedAt: startedAt)
            // The cloud badge is not decoration: while this engine is active
            // the audio WILL leave the device, and the user must see it.
            let base = enginePreference == .cloud
                ? "Cloud dictation — audio leaves this iPhone"
                : "Live bridge active"
            statusMessage = engineFallbackNote.map { "\(base) — \($0)" } ?? base
            startElapsedTimer(from: startedAt)
            startMaxDurationTimer()
            HapticPlayer.listeningStarted()
            UIAccessibility.post(notification: .announcement, argument: "Listening")
            Task { await polisher.prewarm() }
        } catch {
            // If the user cancelled mid-warm-up, abortWarmup already cleaned
            // up and set a friendly status; a late failure from the torn-down
            // engine must not clobber that with an error state.
            if warmupStarted, warmupToken != sessionID {
                await transcriber.unload()
                return
            }
            warmupToken = nil
            activityController.end(immediately: true)
            fail(error)
            // Tear down whatever the engine half-started (audio session,
            // stream). On a warm-up timeout the engine may still be
            // unwinding: `startLiveWithWarmupDeadline` owns the teardown in
            // that case, and unloading a second time would race it.
            if !isWarmupTimeout(error) {
                await transcriber.unload()
            }
        }
    }

    private func isWarmupTimeout(_ error: Error) -> Bool {
        (error as? FlowBridgeError) == .warmupTimedOut
    }

    /// Runs the engine warm-up against a hard deadline: an engine that hangs
    /// while loading (model load, speech-asset install) must not pin the app
    /// in `.warming` with the mic indicator and Live Activity held.
    ///
    /// The engine's own errors propagate. If the deadline wins, the start
    /// is abandoned and `FlowBridgeError.warmupTimedOut` is thrown; the
    /// engine is torn down by the deadline's own `onAbandon` hook rather
    /// than here, because it may still be mid-start.
    private func startLiveWithWarmupDeadline(sessionID: UUID) async throws {
        let engine = transcriber
        do {
            try await withDeadline(
                .seconds(FlowBridgeConstants.warmupTimeoutSeconds),
                onTimeout: { throw FlowBridgeError.warmupTimedOut },
                operation: {
                    try await engine.startLiveTranscription(sessionID: sessionID)
                },
                // The engine is no longer needed either way: the session
                // is already failed, so release the model and any half
                // started audio session as soon as it unwinds.
                onAbandon: { await engine.unload() }
            )
        } catch let error as FlowBridgeError {
            throw error
        } catch {
            throw FlowBridgeError.recorderFailed(error.localizedDescription)
        }
    }

    /// User-initiated cancel while the engine is still warming up.
    private func abortWarmup() async {
        guard case .warming = state else { return }
        warmupToken = nil
        activityController.end(immediately: true)
        state = .idle
        statusMessage = "Dictation cancelled"
        await transcriber.unload()
    }

    private func stopRecordingAndTranscribe(skipPolish: Bool = false) async {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
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
            state = .transcribing
            activityController.update(
                phase: .transcribing,
                transcriptPreview: LiveTranscriptStore.latest()?.text ?? "",
                startedAt: recordingStartedAt
            )

            let record = try await transcriber.stopLiveTranscription(duration: duration)

            // Deterministic spoken commands first ("punto", "a capo", …),
            // then the on-device polish with the current tone target. The
            // engine's verbatim text always survives in rawText.
            var workingText = record.text
            if Self.voiceCommandsEnabled {
                workingText = VoiceCommandProcessor.apply(to: workingText)
            }
            if !skipPolish {
                let tone = toneStore?.currentTone() ?? .neutral
                workingText = await polishBounded(workingText, tone: tone)
            }
            let finalRecord = workingText == record.text ? record : record.polished(workingText)

            try? await historyStore?.add(finalRecord)
            statsStore?.record(text: finalRecord.text, audioDuration: duration)

            let delivered = sessionAppendedRecord(for: finalRecord) ?? finalRecord
            try transcriptStore?.save(delivered)
            lastTranscript = delivered
            UIPasteboard.general.string = delivered.text
            state = .ready
            statusMessage = delivered.id == finalRecord.id ? "Clipboard updated" : "Appended to previous dictation"
            activityController.finish(transcriptPreview: delivered.text, startedAt: recordingStartedAt)
            HapticPlayer.transcriptReady()
            UIAccessibility.post(notification: .announcement, argument: "Transcript ready")
        } catch {
            activityController.finish(transcriptPreview: "", startedAt: recordingStartedAt, failed: true)
            fail(error)
        }

        // Queued-audio work (share extension) that arrived while this
        // transcription ran was left in the store: drain it now that the
        // coordinator is free, instead of waiting for the next activation.
        await consumePendingCommand()
    }

    /// Polish with a hard latency budget: transcripts over the length cap
    /// skip the model entirely, and a polish slower than the deadline is
    /// abandoned in favor of the raw text. Stop-to-ready stays bounded no
    /// matter what the model does.
    private func polishBounded(_ text: String, tone: ToneProfile) async -> String {
        guard text.count <= FlowBridgeConstants.maxPolishCharacters else { return text }
        let polisher = self.polisher

        // The deadline wins over the raw text, and the polish itself is
        // abandoned (not cancelled: FoundationModels does not reliably
        // observe cancellation) — its result is simply discarded.
        return (try? await withDeadline(
            .seconds(FlowBridgeConstants.polishDeadlineSeconds),
            onTimeout: { text },
            operation: {
                await polisher.polish(text, tone: tone)
            }
        )) ?? text
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
              record.createdAt.timeIntervalSince(last.createdAt) <= window,
              // Chains don't grow forever: UserDefaults and the clipboard
              // are not blob stores. Past the cap, start a fresh record.
              last.text.count + record.text.count + 1 <= FlowBridgeConstants.sessionAppendMaxCharacters else {
            return nil
        }

        return TranscriptRecord(
            text: last.text + " " + record.text,
            language: record.language,
            audioDuration: last.audioDuration + record.audioDuration,
            source: .microphone
        )
    }

    /// Streams the latest live snapshot into the Live Activity while
    /// recording (triggered by the Darwin notification the engine posts on
    /// every snapshot write).
    private func pushLiveSnapshotToActivity() {
        guard case .recording(let startedAt) = state, activityController.isActive else { return }
        guard let snapshot = LiveTranscriptStore.latest(), snapshot.isRecording else { return }

        // Engines can emit many snapshots per second; the island only needs
        // changed content at a human cadence. Dropped frames are fine — the
        // next snapshot supersedes them.
        let now = Date()
        guard snapshot.text != lastActivityPreview,
              now.timeIntervalSince(lastActivityPushAt) >= FlowBridgeConstants.liveActivityMinUpdateInterval else {
            return
        }
        lastActivityPreview = snapshot.text
        lastActivityPushAt = now

        activityController.update(
            phase: .recording,
            transcriptPreview: snapshot.text,
            startedAt: startedAt
        )
    }

    private func processQueuedAudioIfNeeded() async {
        // Never start a file transcription while the engine is busy with a
        // live session (or another job): a concurrent CoreML decode on the
        // same models is a crash, and it would clobber the .recording state,
        // orphaning the Live Activity and the audio session.
        switch state {
        case .idle, .ready, .failed:
            break
        case .warming, .recording, .transcribing:
            return
        }

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
            let record = try await transcriber.transcribe(recording: recording, source: .sharedAudio)
            try transcriptStore?.save(record)
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

        // Cloud upload bodies orphaned by a kill mid-upload: a copy of a WAV
        // that is still here, so only disk space is at stake.
        AudioSafetyBuffer.removeStaleUploadBodies(in: directory)
        defer { refreshUnrecoveredDictations() }

        let pending = AudioSafetyBuffer.pendingRecordings(in: directory)
        guard !pending.isEmpty else { return }

        for recording in pending {
            // A file automatic recovery gave up on is left alone: it stays
            // on disk for the user to retry or discard from Settings, but
            // retrying it on every launch only burns battery and startup.
            if recording.isExhausted {
                continue
            }

            guard recording.duration >= FlowBridgeConstants.safetyBufferMinimumRecoverySeconds else {
                // Sub-second holds no speech: nothing worth recovering.
                AudioSafetyBuffer.remove(recording)
                continue
            }

            // Count the attempt BEFORE making it: a recovery that kills the
            // process (jetsam on a long decode) must still move the file
            // towards being left alone, or it would crash every launch.
            guard let attempt = AudioSafetyBuffer.recordRecoveryAttempt(recording) else {
                continue
            }

            state = .transcribing
            statusMessage = "Recovering interrupted dictation"

            if await transcribeRecovered(attempt, forgiveTransient: true) {
                statusMessage = "Recovered interrupted dictation"
            } else {
                state = .idle
                statusMessage = "Interrupted dictation could not be recovered"
            }
        }
    }

    /// Transcribes a safety-buffer WAV and, only once the transcript is
    /// safely stored, deletes it. On failure the file stays: it is still the
    /// user's dictation and the only copy of it. With `forgiveTransient`, a
    /// transient failure (no network for the cloud engine) gives the attempt
    /// back, because the audio was never the problem.
    private func transcribeRecovered(
        _ recording: AudioSafetyBuffer.PendingRecording,
        forgiveTransient: Bool
    ) async -> Bool {
        do {
            let audio = RecordedAudio(url: recording.url, duration: recording.duration)
            let record = try await transcriber.transcribe(recording: audio, source: .recovered)
            try transcriptStore?.save(record)
            lastTranscript = record
            UIPasteboard.general.string = record.text
            state = .ready
            HapticPlayer.transcriptReady()
            AudioSafetyBuffer.remove(recording)
            return true
        } catch {
            if forgiveTransient, error is URLError {
                AudioSafetyBuffer.withdrawRecoveryAttempt(recording)
            }
            return false
        }
    }

    // MARK: - Unrecovered dictations (Settings)

    /// Re-reads the recordings automatic recovery gave up on.
    func refreshUnrecoveredDictations() {
        guard let directory = try? AudioSafetyBuffer.defaultDirectory() else {
            unrecoveredDictations = []
            return
        }
        unrecoveredDictations = AudioSafetyBuffer.exhaustedRecordings(in: directory)
    }

    /// User-initiated retry of an exhausted recording. The attempt counter
    /// restarts: this is a deliberate retry, not the launch loop. Returns
    /// false (and leaves the file) when the coordinator is busy or the
    /// transcription fails again.
    @discardableResult
    func retryUnrecoveredDictation(_ recording: AudioSafetyBuffer.PendingRecording) async -> Bool {
        switch state {
        case .idle, .ready, .failed:
            break
        case .warming, .recording, .transcribing:
            statusMessage = FlowBridgeError.dictationBusy.errorDescription
            return false
        }
        defer { refreshUnrecoveredDictations() }

        await refreshEngineIfNeeded()
        guard let reset = AudioSafetyBuffer.resetRecoveryAttempts(recording),
              let attempt = AudioSafetyBuffer.recordRecoveryAttempt(reset) else {
            statusMessage = "The recording could not be opened"
            return false
        }

        state = .transcribing
        statusMessage = "Transcribing saved dictation"
        if await transcribeRecovered(attempt, forgiveTransient: false) {
            statusMessage = "Saved dictation transcribed — clipboard updated"
            return true
        }
        // Back among the exhausted: the user retried by hand, so the
        // launch loop should not pick it up again on its own.
        var parked = attempt
        while !parked.isExhausted, let next = AudioSafetyBuffer.recordRecoveryAttempt(parked) {
            parked = next
        }
        state = .idle
        statusMessage = "The saved dictation could not be transcribed"
        return false
    }

    /// Deletes an exhausted recording at the user's explicit request — the
    /// only path, besides a stored transcript, that removes audio.
    func discardUnrecoveredDictation(_ recording: AudioSafetyBuffer.PendingRecording) {
        AudioSafetyBuffer.remove(recording)
        refreshUnrecoveredDictations()
    }

    private func stopIfRecording() async {
        switch state {
        case .recording:
            await stopRecordingAndTranscribe()
        case .warming:
            await abortWarmup()
        case .idle, .ready, .failed, .transcribing:
            break
        }
    }

    private func handleMemoryWarning() async {
        switch state {
        case .recording:
            // Under memory pressure the last thing to do is spin up the
            // polisher LLM: finalize with the raw transcript and free memory.
            await stopRecordingAndTranscribe(skipPolish: true)
        case .warming:
            await abortWarmup()
        case .idle, .ready, .failed, .transcribing:
            break
        }
        await transcriber.unload()
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
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message)
        statusMessage = message
        HapticPlayer.failed()
    }
}
