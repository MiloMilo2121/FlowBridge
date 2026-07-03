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

    /// One local-calendar day of dictation. `day` is a "yyyy-MM-dd" key so
    /// buckets sort lexicographically in chronological order.
    public struct DayStat: Codable, Equatable, Sendable {
        public var day: String
        public var sessions: Int
        public var words: Int
        public var speakingSeconds: TimeInterval

        public init(day: String, sessions: Int = 0, words: Int = 0, speakingSeconds: TimeInterval = 0) {
            self.day = day
            self.sessions = sessions
            self.words = words
            self.speakingSeconds = speakingSeconds
        }

        public var wordsPerMinute: Double {
            guard speakingSeconds > 0 else { return 0 }
            return Double(words) / (speakingSeconds / 60)
        }
    }

    public struct RecordOutcome: Equatable, Sendable {
        /// Consecutive days (ending today) with at least one dictation.
        public let streakDays: Int
        /// True when this session is the first of its day.
        public let isNewStreakDay: Bool
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

    @discardableResult
    public func record(
        text: String,
        audioDuration: TimeInterval,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RecordOutcome {
        let words = Self.wordCount(of: text)
        let seconds = max(0, audioDuration)

        // Lifetime totals stay under the original key: old installs keep
        // their numbers with zero migration.
        var current = stats()
        current.sessions += 1
        current.words += words
        current.speakingSeconds += seconds
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: FlowBridgeConstants.statsKey)
        }

        // Upsert today's bucket.
        let key = Self.dayKey(for: now, calendar: calendar)
        var days = allDaily()
        let isNewStreakDay: Bool
        if let index = days.firstIndex(where: { $0.day == key }) {
            days[index].sessions += 1
            days[index].words += words
            days[index].speakingSeconds += seconds
            isNewStreakDay = false
        } else {
            days.append(DayStat(day: key, sessions: 1, words: words, speakingSeconds: seconds))
            isNewStreakDay = true
        }
        days.sort { $0.day < $1.day }
        if days.count > FlowBridgeConstants.dailyStatsCapacity {
            days.removeFirst(days.count - FlowBridgeConstants.dailyStatsCapacity)
        }
        saveDaily(days)

        return RecordOutcome(
            streakDays: currentStreak(asOf: now, calendar: calendar),
            isNewStreakDay: isNewStreakDay
        )
    }

    /// The last `dayCount` days ending on `date`, zero-filled so charts get
    /// a continuous axis even for days without dictations.
    public func daily(last dayCount: Int, endingOn date: Date = Date(), calendar: Calendar = .current) -> [DayStat] {
        let byDay = Dictionary(allDaily().map { ($0.day, $0) }, uniquingKeysWith: { _, new in new })
        let end = calendar.startOfDay(for: date)
        var result: [DayStat] = []
        result.reserveCapacity(dayCount)
        for offset in stride(from: dayCount - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { continue }
            let key = Self.dayKey(for: day, calendar: calendar)
            result.append(byDay[key] ?? DayStat(day: key))
        }
        return result
    }

    /// Consecutive dictation days ending today — or yesterday, so the streak
    /// isn't "lost" before the day's first session.
    public func currentStreak(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(allDaily().map(\.day))
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: date)
        if !days.contains(Self.dayKey(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(Self.dayKey(for: cursor, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public func reset() {
        defaults.removeObject(forKey: FlowBridgeConstants.statsKey)
        defaults.removeObject(forKey: FlowBridgeConstants.dailyStatsKey)
    }

    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func allDaily() -> [DayStat] {
        guard let data = defaults.data(forKey: FlowBridgeConstants.dailyStatsKey),
              let days = try? JSONDecoder().decode([DayStat].self, from: data) else {
            return []
        }
        return days
    }

    private func saveDaily(_ days: [DayStat]) {
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: FlowBridgeConstants.dailyStatsKey)
        }
    }
}
