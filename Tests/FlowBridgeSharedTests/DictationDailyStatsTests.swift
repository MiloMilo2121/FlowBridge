import FlowBridgeShared
import Foundation
import XCTest

final class DictationDailyStatsTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeStore() throws -> DictationStatsStore {
        let suiteName = "daily-stats-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return try DictationStatsStore(defaults: defaults)
    }

    private func day(_ offset: Int, from reference: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference))!
            .addingTimeInterval(10 * 3600)
    }

    func testRecordCreatesAndUpsertsDayBucket() throws {
        let store = try makeStore()
        let today = day(0)

        let first = store.record(text: "one two three", audioDuration: 6, now: today)
        XCTAssertTrue(first.isNewStreakDay)
        XCTAssertEqual(first.streakDays, 1)

        let second = store.record(text: "four five", audioDuration: 4, now: today.addingTimeInterval(3600))
        XCTAssertFalse(second.isNewStreakDay)
        XCTAssertEqual(second.streakDays, 1)

        let days = store.daily(last: 1, endingOn: today)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].sessions, 2)
        XCTAssertEqual(days[0].words, 5)
        XCTAssertEqual(days[0].speakingSeconds, 10, accuracy: 0.001)
    }

    func testStreakCountsConsecutiveDaysAndBreaksOnGap() throws {
        let store = try makeStore()

        // Three consecutive days ending today, after a gap from an older day.
        store.record(text: "old", audioDuration: 1, now: day(-6))
        store.record(text: "a", audioDuration: 1, now: day(-2))
        store.record(text: "b", audioDuration: 1, now: day(-1))
        let outcome = store.record(text: "c", audioDuration: 1, now: day(0))

        XCTAssertEqual(outcome.streakDays, 3)
        XCTAssertEqual(store.currentStreak(asOf: day(0)), 3)
    }

    func testStreakSurvivesBeforeTodaysFirstSession() throws {
        let store = try makeStore()
        store.record(text: "a", audioDuration: 1, now: day(-2))
        store.record(text: "b", audioDuration: 1, now: day(-1))

        // Today has no session yet: the streak counts from yesterday instead
        // of reading as lost.
        XCTAssertEqual(store.currentStreak(asOf: day(0)), 2)
    }

    func testDailyZeroFillsMissingDays() throws {
        let store = try makeStore()
        store.record(text: "one two", audioDuration: 2, now: day(-3))
        store.record(text: "three", audioDuration: 1, now: day(0))

        let days = store.daily(last: 5, endingOn: day(0))
        XCTAssertEqual(days.count, 5)
        XCTAssertEqual(days.map(\.sessions), [0, 1, 0, 0, 1])
        XCTAssertEqual(days[1].words, 2)
        XCTAssertEqual(days[4].words, 1)
    }

    func testLifetimeTotalsKeepAccumulatingAlongsideDailyBuckets() throws {
        let store = try makeStore()
        store.record(text: "one two three", audioDuration: 30, now: day(-1))
        store.record(text: "four five", audioDuration: 30, now: day(0))

        let stats = store.stats()
        XCTAssertEqual(stats.sessions, 2)
        XCTAssertEqual(stats.words, 5)
        XCTAssertEqual(stats.speakingSeconds, 60, accuracy: 0.001)
    }

    func testCapacityCapDropsOldestDays() throws {
        let store = try makeStore()
        let total = FlowBridgeConstants.dailyStatsCapacity + 5
        for offset in stride(from: total - 1, through: 0, by: -1) {
            store.record(text: "word", audioDuration: 1, now: day(-offset))
        }

        let all = store.daily(last: total, endingOn: day(0))
        let recorded = all.filter { $0.sessions > 0 }
        XCTAssertEqual(recorded.count, FlowBridgeConstants.dailyStatsCapacity)
        // The oldest five days fell off the front.
        XCTAssertEqual(all.prefix(5).map(\.sessions), [0, 0, 0, 0, 0])
    }

    func testResetClearsDailyBucketsAndTotals() throws {
        let store = try makeStore()
        store.record(text: "one", audioDuration: 1, now: day(0))
        store.reset()

        XCTAssertEqual(store.stats(), DictationStatsStore.Stats())
        XCTAssertEqual(store.currentStreak(asOf: day(0)), 0)
        XCTAssertTrue(store.daily(last: 7, endingOn: day(0)).allSatisfy { $0.sessions == 0 })
    }
}
