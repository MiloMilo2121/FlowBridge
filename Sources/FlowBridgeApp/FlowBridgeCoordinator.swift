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

    private let transcriber = CloudEngine()
    private let activityController = DictationActivityController()
    private var transcriptStore: TranscriptStore?
    private var historyStore: TranscriptHistoryStore?
    private var pendingCommandStore: PendingCommandStore?
    private var elapsedTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var commandObserver: DarwinNotificationObserver?
    private var liveSnapshotObserver: DarwinNotificationObserver?
    private var lastActivityPreview = ""
    private var lastActivityPushAt = Date.distantPast
    init() {
        // Handlers go in here, not in `bootstrap()`: an intent can be the
        // very first code to run in this process, and a start request that
        // finds no handler throws, which opens the app instead of just
        // dictating. `AppDelegate` touches `.shared` at launch so this runs
        // before any intent can.
        registerCommandHub()
    }

    deinit {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
    }

    func bootstrap() async {
        transcriptStore = try? TranscriptStore()
        historyStore = try? TranscriptHistoryStore()
        pendingCommandStore = try? PendingCommandStore()
        lastTranscript = transcriptStore?.latest()
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
        case .recording:
            // Already started: the request is satisfied.
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
            case .idle, .ready, .failed, .transcribing:
                break
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

    func copyLastTranscript() async {
        guard let text = lastTranscript?.text else { return }
        UIPasteboard.general.string = text
        HapticPlayer.transcriptReady()
    }

    /// - Parameter requiresActivity: background starts only. Without a
    ///   visible Live Activity the system tears the audio down, so a refused
    ///   activity request fails the start.
    private func startRecording(requestPermission: Bool = true, requiresActivity: Bool = false) async {
        // Only a settled coordinator may start: during recording or
        // transcription (including recovery) a start would overwrite the
        // state of the work in flight.
        switch state {
        case .idle, .ready, .failed:
            break
        case .recording, .transcribing:
            return
        }
        let startedAt = Date()
        let sessionID = UUID()
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

            lastActivityPreview = ""
            lastActivityPushAt = .distantPast
            // The Live Activity goes up first: background starts via
            // AudioRecordingIntent require a visible activity to keep audio.
            let activityStarted = activityController.start(sessionID: sessionID, startedAt: startedAt)
            if requiresActivity, !activityStarted {
                throw FlowBridgeError.liveActivityUnavailable
            }
            do {
                try await transcriber.startLiveTranscription(sessionID: sessionID)
            } catch let error as FlowBridgeError {
                throw error
            } catch {
                throw FlowBridgeError.recorderFailed(error.localizedDescription)
            }

            state = .recording(startedAt: startedAt)
            statusMessage = "Recording — audio is uploaded when you stop"
            startElapsedTimer(from: startedAt)
            startMaxDurationTimer()
            HapticPlayer.listeningStarted()
            UIAccessibility.post(notification: .announcement, argument: "Listening")
        } catch {
            activityController.end(immediately: true)
            fail(error)
            await transcriber.unload()
        }
    }

    private func stopRecordingAndTranscribe() async {
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
            try? await historyStore?.add(record)
            try transcriptStore?.save(record)
            lastTranscript = record
            UIPasteboard.general.string = record.text
            state = .ready
            statusMessage = "Clipboard updated"
            activityController.finish(transcriptPreview: record.text, startedAt: recordingStartedAt)
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
        // Never start a file transcription while a live session runs: it
        // would clobber the .recording state, orphaning the Live Activity
        // and the audio session.
        switch state {
        case .idle, .ready, .failed:
            break
        case .recording, .transcribing:
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
            try? await historyStore?.add(record)
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
            try? await historyStore?.add(record)
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
        case .recording, .transcribing:
            statusMessage = FlowBridgeError.dictationBusy.errorDescription
            return false
        }
        defer { refreshUnrecoveredDictations() }

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
        case .idle, .ready, .failed, .transcribing:
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
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        state = .failed(message)
        statusMessage = message
        HapticPlayer.failed()
    }
}
