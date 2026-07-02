import FlowBridgeShared
import Foundation
import XCTest

final class VoiceCommandProcessorTests: XCTestCase {
    func testItalianPunctuationCommands() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "ciao Marco virgola come stai punto interrogativo"),
            "Ciao Marco, come stai?"
        )
    }

    func testEnglishPunctuationCommands() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "hello Marco comma how are you question mark"),
            "Hello Marco, how are you?"
        )
    }

    func testPeriodAndCapitalization() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "prima frase punto seconda frase punto"),
            "Prima frase. Seconda frase."
        )
    }

    func testNewLineAndParagraph() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "primo punto a capo secondo punto nuovo paragrafo terzo"),
            "Primo.\nSecondo.\n\nTerzo"
        )
    }

    func testLongerCommandWinsOverShorter() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "davvero punto esclamativo"),
            "Davvero!"
        )
    }

    func testWordsContainingCommandAreNotTouched() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "un appunto importante"),
            "Un appunto importante"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "la puntominosa"),
            "La puntominosa"
        )
    }

    func testExistingPunctuationFromEngineIsNotDuplicated() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "ciao virgola, come va"),
            "Ciao, come va"
        )
    }
}
