import CoreHaptics
import FlowBridgeShared
import UIKit

/// The fixed haptic vocabulary (see KILLER_FEATURES_V2.md §2.2): each event
/// has exactly one pattern, never reused for another meaning — the app is
/// fully usable from the pocket. Designed CoreHaptics patterns first, the
/// original UIFeedback taps as the fallback whenever the engine is
/// unavailable. CoreHaptics ignores the system haptics setting, so the
/// app-level master switch guards every call.
@MainActor
enum HapticPlayer {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    static var isEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.hapticsEnabledKey) as? Bool ?? true
    }

    /// Called at the moment of intent (state → warming): spins the engine up
    /// and readies the fallback generators so the first pattern has no lag.
    static func prepare() {
        guard isEnabled else { return }
        HapticEngineController.shared.warmUp()
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        notification.prepare()
    }

    /// "Heartbeat up": two rising taps — I'm listening.
    static func listeningStarted() {
        guard isEnabled else { return }
        let played = HapticEngineController.shared.play([
            .transient(at: 0, intensity: 0.45, sharpness: 0.35),
            .transient(at: 0.08, intensity: 0.85, sharpness: 0.5),
        ])
        guard !played else { return }
        lightImpact.impactOccurred(intensity: 0.5)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            mediumImpact.impactOccurred(intensity: 0.9)
        }
    }

    /// "Heartbeat down": mirror of the start — I've stopped listening.
    static func listeningStopped() {
        guard isEnabled else { return }
        let played = HapticEngineController.shared.play([
            .transient(at: 0, intensity: 0.85, sharpness: 0.5),
            .transient(at: 0.08, intensity: 0.45, sharpness: 0.35),
        ])
        guard !played else { return }
        mediumImpact.impactOccurred(intensity: 0.9)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            lightImpact.impactOccurred(intensity: 0.5)
        }
    }

    /// "Crystal": the transcript is ready and delivered — one hard, bright
    /// tap with a short shimmer tail.
    static func transcriptReady() {
        guard isEnabled else { return }
        let played = HapticEngineController.shared.play([
            .transient(at: 0, intensity: 1.0, sharpness: 0.9),
            .continuous(at: 0.02, duration: 0.06, intensity: 0.3, sharpness: 0.25),
        ])
        guard !played else { return }
        notification.notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            rigidImpact.impactOccurred(intensity: 0.6)
        }
    }

    /// Soft rumble — something failed, nothing was lost.
    static func failed() {
        guard isEnabled else { return }
        let played = HapticEngineController.shared.play([
            .continuous(at: 0, duration: 0.2, intensity: 0.5, sharpness: 0.12),
        ])
        guard !played else { return }
        notification.notificationOccurred(.error)
    }

    /// Micro-transient synced to a voice peak while recording. CoreHaptics
    /// only — UIFeedback would be too blunt at this cadence.
    static func voicePeak(level: Float) {
        guard isEnabled else { return }
        HapticEngineController.shared.play([
            .transient(at: 0, intensity: 0.2 + 0.4 * min(max(level, 0), 1), sharpness: 0.6),
        ])
    }

    /// Barely-perceptible tick when a streamed word lands.
    static func wordLanded() {
        guard isEnabled else { return }
        HapticEngineController.shared.play([
            .transient(at: 0, intensity: 0.15, sharpness: 0.66),
        ])
    }
}
