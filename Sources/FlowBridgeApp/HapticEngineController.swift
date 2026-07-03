import CoreHaptics
import Foundation

/// Lazily-created `CHHapticEngine` with auto-shutdown, recreated after
/// system resets. Every failure returns false so callers fall back to the
/// UIFeedback generators — the vocabulary never goes silent.
@MainActor
final class HapticEngineController {
    static let shared = HapticEngineController()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func warmUp() {
        _ = readyEngine()
    }

    @discardableResult
    func play(_ events: [CHHapticEvent]) -> Bool {
        guard let engine = readyEngine() else { return false }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            self.engine = nil
            return false
        }
    }

    private func readyEngine() -> CHHapticEngine? {
        guard supportsHaptics else { return nil }
        if let engine {
            return engine
        }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.engine = nil
                }
            }
            try engine.start()
            self.engine = engine
            return engine
        } catch {
            return nil
        }
    }
}

extension CHHapticEvent {
    static func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    static func continuous(at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }
}
