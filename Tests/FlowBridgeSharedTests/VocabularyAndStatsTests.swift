import FlowBridgeShared
import Foundation
import XCTest

final class VocabularyStoreTests: XCTestCase {
    func testAddRemoveAndDeduplication() throws {
        let store = try VocabularyStore(defaults: makeDefaults())
        try store.add("Milanello")
        try store.add("  WhisperKit  ")
        try store.add("milanello")
        XCTAssertEqual(store.terms(), ["Milanello", "WhisperKit"])

        try store.remove("MILANELLO")
        XCTAssertEqual(store.terms(), ["WhisperKit"])
    }

    func testPromptBiasText() throws {
        let store = try VocabularyStore(defaults: makeDefaults())
        XCTAssertNil(store.promptBiasText())

        try store.add("Milanello")
        try store.add("FlowBridge")
        XCTAssertEqual(store.promptBiasText(), "Glossary: Milanello, FlowBridge.")
    }

    func testCapacityKeepsMostRecent() throws {
        let store = try VocabularyStore(defaults: makeDefaults())
        for index in 1...(VocabularyStore.maxTerms + 10) {
            try store.add("term\(index)")
        }
        let terms = store.terms()
        XCTAssertEqual(terms.count, VocabularyStore.maxTerms)
        XCTAssertFalse(terms.contains("term1"))
        XCTAssertTrue(terms.contains("term\(VocabularyStore.maxTerms + 10)"))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "VocabularyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

final class DictationStatsStoreTests: XCTestCase {
    func testRecordAccumulates() throws {
        let store = try DictationStatsStore(defaults: makeDefaults())
        store.record(text: "una due tre quattro", audioDuration: 10)
        store.record(text: "cinque sei", audioDuration: 5)

        let stats = store.stats()
        XCTAssertEqual(stats.sessions, 2)
        XCTAssertEqual(stats.words, 6)
        XCTAssertEqual(stats.speakingSeconds, 15)
    }

    func testTimeSavedIsTypingMinusSpeaking() throws {
        let store = try DictationStatsStore(defaults: makeDefaults())
        // 380 words: ~10 min of typing at 38 wpm, spoken in 2 min → ~8 saved.
        let words = Array(repeating: "parola", count: 380).joined(separator: " ")
        store.record(text: words, audioDuration: 120)

        let stats = store.stats()
        XCTAssertEqual(stats.timeSavedMinutes, 8, accuracy: 0.01)
        XCTAssertEqual(stats.wordsPerMinute, 190, accuracy: 0.01)
    }

    func testResetClears() throws {
        let store = try DictationStatsStore(defaults: makeDefaults())
        store.record(text: "ciao", audioDuration: 1)
        store.reset()
        XCTAssertEqual(store.stats(), DictationStatsStore.Stats())
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "StatsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

final class ToneContextStoreTests: XCTestCase {
    func testFreshHintWinsOverDefault() throws {
        let defaults = makeDefaults()
        let store = try ToneContextStore(defaults: defaults)
        store.setDefaultTone(.formal)
        store.writeHint(ToneHint(profile: .casual))
        XCTAssertEqual(store.currentTone(), .casual)
    }

    func testStaleHintFallsBackToDefault() throws {
        let defaults = makeDefaults()
        let store = try ToneContextStore(defaults: defaults)
        store.setDefaultTone(.formal)
        store.writeHint(ToneHint(profile: .casual, capturedAt: Date(timeIntervalSinceNow: -3600)))
        XCTAssertEqual(store.currentTone(), .formal)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ToneTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
