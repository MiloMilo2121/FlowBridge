import FlowBridgeShared
import Foundation

/// Streams the recording's haptic texture: micro-transients on voice peaks
/// (30Hz poll of the level meter, rising-edge gated) and a tiny tick when a
/// committed word lands. Both are user-visible settings; peaks default OFF,
/// word ticks default ON.
@MainActor
final class RecordingFeedbackDriver {
    private var task: Task<Void, Never>?
    private var lastPeakAt = Date.distantPast
    private var lastWordTickAt = Date.distantPast
    private var lastCommittedWordCount = 0
    private var wasAbovePeak = false

    static var voicePeaksEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.hapticVoicePeaksEnabledKey) as? Bool ?? false
    }

    static var wordTicksEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.hapticWordTickEnabledKey) as? Bool ?? true
    }

    func start() {
        stop()
        lastCommittedWordCount = 0
        wasAbovePeak = false
        guard Self.voicePeaksEnabled, HapticPlayer.isEnabled else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.pollLevel()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Called on every live snapshot: ticks once per newly committed word,
    /// rate-limited so fast speech stays a texture, not a buzz.
    func noteSnapshot(_ snapshot: LiveTranscriptSnapshot) {
        guard Self.wordTicksEnabled, HapticPlayer.isEnabled else { return }
        let total = snapshot.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let volatile = snapshot.previewText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let committed = max(0, total - volatile)

        guard committed > lastCommittedWordCount else {
            lastCommittedWordCount = min(lastCommittedWordCount, committed)
            return
        }
        lastCommittedWordCount = committed

        let now = Date()
        guard now.timeIntervalSince(lastWordTickAt) >= 0.09 else { return }
        lastWordTickAt = now
        HapticPlayer.wordLanded()
    }

    private func pollLevel() {
        let level = AudioLevelMeter.shared.latestLevel
        let above = level > 0.58

        defer { wasAbovePeak = above }
        guard above, !wasAbovePeak else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPeakAt) >= 0.14 else { return }
        lastPeakAt = now
        HapticPlayer.voicePeak(level: level)
    }
}
