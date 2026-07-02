import AVFoundation
import FlowBridgeShared
import Foundation

struct RecordedAudio: Sendable {
    let url: URL
    let duration: TimeInterval
}

actor FlowBridgeRecorder {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    /// Whether recording can start without showing a permission prompt —
    /// the prerequisite for background starts, where no prompt can appear.
    func hasGrantedPermission() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func start() async throws {
        guard recorder == nil else {
            throw FlowBridgeError.alreadyRecording
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetoothHFP, .duckOthers])
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredInputNumberOfChannels(1)
        try session.setActive(true, options: [])

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlowBridgeRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = false
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw FlowBridgeError.recorderFailed("AVAudioRecorder refused to start.")
        }

        self.recorder = recorder
        recordingURL = url
    }

    func stop() async throws -> RecordedAudio {
        guard let recorder, let recordingURL else {
            throw FlowBridgeError.notRecording
        }

        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            throw FlowBridgeError.recorderFailed("Recorded file was not created.")
        }

        return RecordedAudio(url: recordingURL, duration: duration)
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

