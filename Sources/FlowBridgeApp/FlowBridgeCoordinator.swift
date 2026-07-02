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

    private let recorder = FlowBridgeRecorder()
    private let transcriber: any TranscriptionEngine = EngineFactory.makeCurrent()
    private let activityController = DictationActivityController()
    private let polisher = TranscriptPolisher.shared
    private var transcriptStore: TranscriptStore?
    private var pendingCommandStore: PendingCommandStore?
    private var elapsedTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
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

    deinit {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func bootstrap() async {
        NetworkGuard.install()
        transcriptStore = try? TranscriptStore()
        pendingCommandStore = try? PendingCommandStore()
        lastTranscript = await transcriptStore?.latest()
        registerSystemIntegration()
        await recoverInterruptedDictationIfNeeded()
        await consumePendingCommand()
        await processQueuedAudioIfNeeded()
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
        switch phase {
        case .active:
            await consumePendingCommand()
            await processQueuedAudioIfNeeded()
        case .background:
            if case .recording = state {
                statusMessage = "Live bridge active"
            } else {
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
            statusMessage = "Loading local engine"
            // The Live Activity goes up before the engine warms: the island
            // responds to the trigger instantly, and background starts via
            // AudioRecordingIntent require a visible activity to keep audio.
            activityController.start(sessionID: sessionID, startedAt: startedAt)
            try await transcriber.startLiveTranscription(sessionID: sessionID)
            state = .recording(startedAt: startedAt)
            statusMessage = "Live bridge active"
            startElapsedTimer(from: startedAt)
            startMaxDurationTimer()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await polisher.prewarm() }
        } catch {
            activityController.end(immediately: true)
            fail(error)
        }
    }

    private func stopRecordingAndTranscribe() async {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        recordingElapsed = nil

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
            let polishedText = await polisher.polish(record.text)
            let finalRecord = polishedText == record.text ? record : record.polished(polishedText)

            try await transcriptStore?.save(finalRecord)
            lastTranscript = finalRecord
            UIPasteboard.general.string = finalRecord.text
            state = .ready
            statusMessage = "Clipboard updated"
            activityController.finish(transcriptPreview: finalRecord.text, startedAt: recordingStartedAt)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            activityController.finish(transcriptPreview: "", startedAt: recordingStartedAt, failed: true)
            fail(error)
        }
    }

    /// Streams the latest live snapshot into the Live Activity while
    /// recording (triggered by the Darwin notification the engine posts on
    /// every snapshot write).
    private func pushLiveSnapshotToActivity() {
        guard case .recording(let startedAt) = state, activityController.isActive else { return }
        guard let snapshot = LiveTranscriptStore.latest(), snapshot.isRecording else { return }
        activityController.update(
            phase: .recording,
            transcriptPreview: snapshot.text,
            startedAt: startedAt
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
        if case .recording = state {
            await stopRecordingAndTranscribe()
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
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
