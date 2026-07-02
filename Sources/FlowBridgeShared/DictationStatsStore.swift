import Foundation

/// Cumulative, local-only dictation statistics — the "time given back"
/// counter. No analytics, no network: the numbers exist for the user.
public final class DictationStatsStore: @unchecked Sendable {
    public struct Stats: Codable, Equatable, Sendable {
        public var sessions: Int
        public var words: Int
        public var speakingSeconds: TimeInterval

        public init(sessions: Int = 0, words: Int = 0, speakingSeconds: TimeInterval = 0) {
            self.sessions = sessions
            self.words = words
            self.speakingSeconds = speakingSeconds
        }

        /// Minutes the user did not spend typing: estimated typing time for
        /// the dictated words minus the time actually spent speaking.
        public var timeSavedMinutes: Double {
            let typingMinutes = Double(words) / FlowBridgeConstants.typingWordsPerMinute
            let speakingMinutes = speakingSeconds / 60
            return max(0, typingMinutes - speakingMinutes)
        }

        /// Effective dictation speed; 0 when nothing was recorded yet.
        public var wordsPerMinute: Double {
            guard speakingSeconds > 0 else { return 0 }
            return Double(words) / (speakingSeconds / 60)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
    }

    public func stats() -> Stats {
        guard let data = defaults.data(forKey: FlowBridgeConstants.statsKey),
              let stats = try? JSONDecoder().decode(Stats.self, from: data) else {
            return Stats()
        }
        return stats
    }

    public func record(text: String, audioDuration: TimeInterval) {
        var current = stats()
        current.sessions += 1
        current.words += Self.wordCount(of: text)
        current.speakingSeconds += max(0, audioDuration)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: FlowBridgeConstants.statsKey)
        }
    }

    public func reset() {
        defaults.removeObject(forKey: FlowBridgeConstants.statsKey)
    }

    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
