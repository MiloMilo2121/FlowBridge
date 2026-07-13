import FlowBridgeShared
import Foundation
import XCTest

final class SpeakerTranscriptFormatterTests: XCTestCase {
    typealias Word = SpeakerTranscriptFormatter.Word
    typealias Segment = SpeakerTranscriptFormatter.Segment

    // MARK: - Rendering

    func testSingleSpeakerStaysFlat() {
        let words = [
            Word(text: "ciao", start: 0.0, end: 0.4, speaker: "speaker_0"),
            Word(text: "come", start: 0.5, end: 0.8, speaker: "speaker_0"),
            Word(text: "stai?", start: 0.9, end: 1.3, speaker: "speaker_0")
        ]
        let text = SpeakerTranscriptFormatter.labeledText(words: words)
        XCTAssertEqual(text, "Ciao come stai?")
        XCTAssertNil(SpeakerTranscriptFormatter.turns(in: text))
    }

    func testTwoSpeakersProduceLabeledTurns() {
        let words = [
            Word(text: "ciao", start: 0.0, end: 0.4, speaker: "B"),
            Word(text: "Marco", start: 0.5, end: 0.9, speaker: "B"),
            Word(text: "ciao,", start: 1.2, end: 1.6, speaker: "A"),
            Word(text: "dimmi", start: 1.7, end: 2.0, speaker: "A"),
            Word(text: "va", start: 2.4, end: 2.6, speaker: "B"),
            Word(text: "bene", start: 2.7, end: 3.0, speaker: "B")
        ]
        let text = SpeakerTranscriptFormatter.labeledText(words: words)
        XCTAssertEqual(text, "Speaker 1: Ciao Marco\n\nSpeaker 2: Ciao, dimmi\n\nSpeaker 1: Va bene")
    }

    func testNumberingFollowsFirstAppearanceNotRawID() {
        let words = [
            Word(text: "prima", start: 0, end: 1, speaker: "speaker_7"),
            Word(text: "seconda", start: 2, end: 3, speaker: "speaker_2")
        ]
        let text = SpeakerTranscriptFormatter.labeledText(words: words)
        XCTAssertTrue(text.hasPrefix("Speaker 1: Prima"))
        XCTAssertTrue(text.contains("Speaker 2: Seconda"))
    }

    func testEmptyAndWhitespaceWordsAreIgnored() {
        XCTAssertEqual(SpeakerTranscriptFormatter.labeledText(words: []), "")
        let words = [
            Word(text: " ", start: 0, end: 1, speaker: "A"),
            Word(text: "solo", start: 1, end: 2, speaker: "B")
        ]
        XCTAssertEqual(SpeakerTranscriptFormatter.labeledText(words: words), "Solo")
    }

    // MARK: - Parsing back

    func testTurnsRoundTrip() {
        let text = "Speaker 1: Ciao Marco\n\nSpeaker 2: Ciao, dimmi\n\nSpeaker 1: Va bene"
        let turns = SpeakerTranscriptFormatter.turns(in: text)
        XCTAssertEqual(turns?.count, 3)
        XCTAssertEqual(turns?[0].label, "Speaker 1")
        XCTAssertEqual(turns?[1].text, "Ciao, dimmi")
        XCTAssertEqual(SpeakerTranscriptFormatter.compose(turns: turns ?? []), text)
        XCTAssertEqual(SpeakerTranscriptFormatter.labels(in: text), ["Speaker 1", "Speaker 2"])
    }

    func testFlatTextIsNotParsedAsTurns() {
        XCTAssertNil(SpeakerTranscriptFormatter.turns(in: "Nota: comprare il latte e poi chiamare Luca"))
        XCTAssertNil(SpeakerTranscriptFormatter.turns(in: "Testo semplice senza etichette"))
        // Content before the first label disqualifies the whole text.
        XCTAssertNil(SpeakerTranscriptFormatter.turns(in: "Intro\nSpeaker 1: ciao\n\nSpeaker 2: ciao"))
        XCTAssertNil(SpeakerTranscriptFormatter.turns(in: ""))
    }

    func testRename() {
        let text = "Speaker 1: Ciao\n\nSpeaker 2: Dimmi\n\nSpeaker 1: Ok"
        let renamed = SpeakerTranscriptFormatter.renamed(text, mapping: ["Speaker 1": "Marco", "Speaker 2": " Anna "])
        XCTAssertEqual(renamed, "Marco: Ciao\n\nAnna: Dimmi\n\nMarco: Ok")
        // Empty mapping values keep the original label; flat text passes through.
        XCTAssertEqual(
            SpeakerTranscriptFormatter.renamed(text, mapping: ["Speaker 1": "  "]),
            text
        )
        XCTAssertEqual(SpeakerTranscriptFormatter.renamed("testo piatto", mapping: ["Speaker 1": "X"]), "testo piatto")
    }

    // MARK: - Word ↔ segment fusion

    func testAssignByMidpointWithNearestFallback() {
        let segments = [
            Segment(start: 0.0, end: 2.0, speaker: "1"),
            Segment(start: 3.0, end: 5.0, speaker: "2")
        ]
        let words: [(text: String, start: TimeInterval, end: TimeInterval)] = [
            ("dentro", 0.5, 1.0),   // midpoint 0.75 → segment 1
            ("limbo", 2.2, 2.6),    // midpoint 2.4 → nearest is segment 1 (0.4 vs 0.6)
            ("dopo", 4.0, 4.5)      // midpoint 4.25 → segment 2
        ]
        let assigned = SpeakerTranscriptFormatter.assign(words: words, to: segments)
        XCTAssertEqual(assigned.map(\.speaker), ["1", "1", "2"])
        XCTAssertEqual(assigned.map(\.text), ["dentro", "limbo", "dopo"])
        XCTAssertTrue(SpeakerTranscriptFormatter.assign(words: words, to: []).isEmpty)
    }

    // MARK: - History rename support

    func testHistoryUpdateTextPreservesIdentityAndPin() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
        let store = try TranscriptHistoryStore(fileURL: url)
        let original = TranscriptRecord(
            text: "Speaker 1: Ciao\n\nSpeaker 2: Dimmi",
            rawText: "ciao dimmi",
            language: "it",
            audioDuration: 4,
            source: .microphone
        )
        try await store.add(original)
        try await store.setPinned(true, id: original.id)

        try await store.updateText(id: original.id, text: "Marco: Ciao\n\nAnna: Dimmi")

        let entry = await store.all().first
        XCTAssertEqual(entry?.record.id, original.id)
        XCTAssertEqual(entry?.record.text, "Marco: Ciao\n\nAnna: Dimmi")
        XCTAssertEqual(entry?.record.rawText, "ciao dimmi")
        XCTAssertEqual(entry?.record.createdAt, original.createdAt)
        XCTAssertEqual(entry?.isPinned, true)

        // Unknown id is a no-op, not an error.
        try await store.updateText(id: UUID(), text: "x")
        let count = await store.all().count
        XCTAssertEqual(count, 1)
    }
}
