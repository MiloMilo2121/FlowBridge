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

    // MARK: - Bare "punto"/"virgola" are also ordinary nouns

    func testBarePuntoInsideOrdinaryProseIsNotACommand() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "a un certo punto ho cambiato punto di vista"),
            "A un certo punto ho cambiato punto di vista"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "punto di vista"),
            "Punto di vista"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "il punto di partenza è questo"),
            "Il punto di partenza è questo"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "quello è un punto di contatto"),
            "Quello è un punto di contatto"
        )
    }

    func testBarePuntoStillCommandsInRealSentencePositions() {
        // End of utterance: the common case.
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "prima frase punto"),
            "Prima frase."
        )
        // Between clauses, with no determiner governing it.
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "prima frase punto seconda frase punto"),
            "Prima frase. Seconda frase."
        )
        // The engine punctuated the utterance: the word closed a thought
        // (the cleanup pass then collapses the doubled marks).
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "prima frase punto, seconda frase"),
            "Prima frase. Seconda frase"
        )
    }

    func testBareVirgolaInsideOrdinaryProseIsNotACommand() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "la virgola divide le frasi"),
            "La virgola divide le frasi"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "metti una virgola qui"),
            "Metti una virgola qui"
        )
    }

    func testExplicitPeriodAndNewLineKeyword() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "prima frase punto e a capo seconda"),
            "Prima frase.\nSeconda"
        )
    }

    func testEnginePunctuationDoesNotTurnTheNounIntoACommand() {
        // The engine punctuates prose too: a comma after the noun is not
        // evidence that the user said "full stop".
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "a un certo punto, ho deciso"),
            "A un certo punto, ho deciso"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "qual è il punto punto interrogativo"),
            "Qual è il punto?"
        )
    }

    func testAdjectiveBetweenDeterminerAndNoun() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "il primo punto è chiaro"),
            "Il primo punto è chiaro"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "manca un altro punto importante"),
            "Manca un altro punto importante"
        )
        // Elisions arrive as one token and are split at the apostrophe.
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "sull'ultimo punto siamo d'accordo"),
            "Sull'ultimo punto siamo d'accordo"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "serve un'altra virgola qui"),
            "Serve un'altra virgola qui"
        )
        // Only true pre-nominal adjectives count: an ordinary noun between a
        // determiner and the word leaves the command alone.
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "ho visto il film punto bello"),
            "Ho visto il film. Bello"
        )
    }

    func testNumberedItemsAreLabelsNotFullStops() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "passiamo al punto due dell'ordine del giorno"),
            "Passiamo al punto due dell'ordine del giorno"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "punto due il bilancio"),
            "Punto due il bilancio"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "vediamo punto 3 del contratto"),
            "Vediamo punto 3 del contratto"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "tre virgola cinque chili"),
            "Tre virgola cinque chili"
        )
        // An ordinal opening the clause is a heading…
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "punto primo il bilancio"),
            "Punto primo il bilancio"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "ordine del giorno a capo punto secondo le assunzioni"),
            "Ordine del giorno\nPunto secondo le assunzioni"
        )
        // …mid-sentence it is what the user dictates next.
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "prima frase punto secondo paragrafo"),
            "Prima frase. Secondo paragrafo"
        )
    }

    func testEnglishPronounIDoesNotBlockTheCommand() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "so do I period"),
            "So do I."
        )
    }

    func testExistingPunctuationFromEngineIsNotDuplicated() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "ciao virgola, come va"),
            "Ciao, come va"
        )
    }

    func testURLsEmailsAndDecimalsSurviveUntouched() {
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "vai su example.com punto"),
            "Vai su example.com."
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "scrivi a marco.rossi@example.com virgola grazie"),
            "Scrivi a marco.rossi@example.com, grazie"
        )
        XCTAssertEqual(
            VoiceCommandProcessor.apply(to: "sono 3.5 chilometri punto ottimo"),
            "Sono 3.5 chilometri. Ottimo"
        )
    }
}
