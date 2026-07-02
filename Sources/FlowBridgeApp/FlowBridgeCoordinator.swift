import FlowBridgeShared
import SwiftUI
import UIKit

@MainActor
final class FlowBridgeCoordinator: ObservableObject {
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
    private let transcriber: any TranscriptionEngine = WhisperEngine()
    private var transcriptStore: TranscriptStore?
    private var pendingCommandStore: PendingCommandStore?
    private var elapsedTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?

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
        await recoverInterruptedDictationIfNeeded()
        await consumePendingCommand()
        await processQueuedAudioIfNeeded()
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

    func copyLastTranscript() async {
        guard let text = lastTranscript?.text else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func unloadModel() async {
        await transcriber.unload()
        statusMessage = "Model unloaded"
    }

    private func startRecording() async {
        do {
            guard await recorder.requestPermission() else {
                throw FlowBridgeError.microphonePermissionDenied
            }

            let startedAt = Date()
            state = .warming
            statusMessage = "Loading local Whisper"
            try await transcriber.startLiveTranscription(sessionID: UUID())
            state = .recording(startedAt: startedAt)
            statusMessage = "Live bridge active"
            startElapsedTimer(from: startedAt)
            startMaxDurationTimer()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            fail(error)
        }
    }

    private func stopRecordingAndTranscribe() async {
        elapsedTask?.cancel()
        maxDurationTask?.cancel()
        recordingElapsed = nil

        do {
            let duration: TimeInterval
            if case .recording(let startedAt) = state {
                duration = Date().timeIntervalSince(startedAt)
            } else {
                duration = 0
            }
            state = .transcribing
            let record = try await transcriber.stopLiveTranscription(duration: duration)
            try await transcriptStore?.save(record)
            lastTranscript = record
            UIPasteboard.general.string = record.text
            state = .ready
            statusMessage = "Clipboard updated"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            fail(error)
        }
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
