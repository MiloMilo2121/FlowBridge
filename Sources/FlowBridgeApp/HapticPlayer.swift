import UIKit

/// One haptic pattern per event, never reused for another meaning, so the
/// app is usable from the pocket.
@MainActor
enum HapticPlayer {
    /// "Heartbeat up": two rising taps — I'm listening.
    static func listeningStarted() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        }
    }

    /// "Heartbeat down": mirror of the start — I've stopped listening.
    static func listeningStopped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        }
    }

    /// "Crystal": the transcript is ready and delivered.
    static func transcriptReady() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
        }
    }

    /// Soft rumble — something failed, nothing was lost.
    static func failed() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
