import FlowBridgeShared
import Foundation
import XCTest

final class WERCalculatorTests: XCTestCase {
    func testPerfectMatchHasZeroErrorRate() {
        let result = WERCalculator.evaluate(
            reference: "Ciao, come stai oggi?",
            hypothesis: "ciao come stai oggi"
        )
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.errorRate, 0)
        XCTAssertEqual(result.referenceWordCount, 4)
    }

    func testTokenizationIgnoresPunctuationAndCase() {
        XCTAssertEqual(
            WERCalculator.tokens(from: "L\u{2019}ho detto: davvero!"),
            ["l'ho", "detto", "davvero"]
        )
    }

    func testSubstitutionIsCounted() {
        let result = WERCalculator.evaluate(
            reference: "il gatto dorme",
            hypothesis: "il cane dorme"
        )
        XCTAssertEqual(result.substitutions, 1)
        XCTAssertEqual(result.insertions, 0)
        XCTAssertEqual(result.deletions, 0)
        XCTAssertEqual(result.errorRate, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testInsertionAndDeletionAreCounted() {
        let insertion = WERCalculator.evaluate(
            reference: "buongiorno a tutti",
            hypothesis: "buongiorno davvero a tutti"
        )
        XCTAssertEqual(insertion.insertions, 1)
        XCTAssertEqual(insertion.errorCount, 1)

        let deletion = WERCalculator.evaluate(
            reference: "buongiorno a tutti",
            hypothesis: "buongiorno tutti"
        )
        XCTAssertEqual(deletion.deletions, 1)
        XCTAssertEqual(deletion.errorCount, 1)
    }

    func testEmptyHypothesisCountsAllDeletions() {
        let result = WERCalculator.evaluate(reference: "una due tre", hypothesis: "")
        XCTAssertEqual(result.deletions, 3)
        XCTAssertEqual(result.errorRate, 1.0)
    }

    func testEmptyReferenceWithHypothesisIsFullError() {
        let result = WERCalculator.evaluate(reference: "", hypothesis: "parole inattese")
        XCTAssertEqual(result.errorRate, 1.0)
    }

    func testEmptyBothIsZero() {
        let result = WERCalculator.evaluate(reference: "", hypothesis: "")
        XCTAssertEqual(result.errorRate, 0)
    }

    func testMixedErrorsMatchKnownAlignment() {
        // reference: "domani vado a roma in treno"
        // hypothesis: "domani vado roma nel treno presto"
        // best alignment: deletion of "a", substitution "in"->"nel", insertion of "presto"
        let result = WERCalculator.evaluate(
            reference: "domani vado a roma in treno",
            hypothesis: "domani vado roma nel treno presto"
        )
        XCTAssertEqual(result.errorCount, 3)
        XCTAssertEqual(result.errorRate, 0.5, accuracy: 0.0001)
    }
}
