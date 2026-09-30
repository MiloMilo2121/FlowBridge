import Foundation

/// The essential spoken commands, applied as deterministic text
/// replacements on the final transcript — instant and predictable, never an
/// LLM interpretation. Italian and English, matched as whole words the
/// engine transcribed (case-insensitive).
///
/// Scope is deliberately tiny ("poche cose fatte bene"): punctuation marks,
/// line breaks, paragraph breaks. Anything richer belongs to the polisher.
///
/// A caveat the sets below make explicit: "punto" and "virgola" are both
/// commands and ordinary Italian nouns, and no rule can separate "prima
/// frase punto" (a full stop) from "a un certo punto" (prose) perfectly.
/// The rule applied is: the word counts as a command unless the
/// surrounding words show it is the noun. That errs toward leaving the word
/// alone, because a stray "." is easy to delete and a dictation that lost a
/// word is not.
public enum VoiceCommandProcessor {
    private struct Command {
        let phrases: [String]
        let replacement: String
        /// Punctuation attaches to the previous word; breaks stand alone.
        let attachesToPreviousWord: Bool
        /// Bare words like "punto" and "virgola" are also ordinary Italian
        /// nouns: "a un certo punto", "punto di vista". Multi-word keywords
        /// ("punto interrogativo") are unambiguous and never need this.
        let requiresContext: Bool
    }

    private static let commands: [Command] = [
        // Order matters: longer phrases first so "punto interrogativo" wins
        // over a bare "punto".
        Command(phrases: ["punto interrogativo", "question mark"], replacement: "?", attachesToPreviousWord: true, requiresContext: false),
        Command(phrases: ["punto esclamativo", "exclamation mark", "exclamation point"], replacement: "!", attachesToPreviousWord: true, requiresContext: false),
        Command(phrases: ["punto e virgola", "semicolon"], replacement: ";", attachesToPreviousWord: true, requiresContext: false),
        Command(phrases: ["punto e a capo", "full stop new line"], replacement: ".\n", attachesToPreviousWord: true, requiresContext: false),
        Command(phrases: ["nuovo paragrafo", "new paragraph"], replacement: "\n\n", attachesToPreviousWord: false, requiresContext: false),
        Command(phrases: ["a capo", "new line"], replacement: "\n", attachesToPreviousWord: false, requiresContext: false),
        Command(phrases: ["due punti", "colon"], replacement: ":", attachesToPreviousWord: true, requiresContext: false),
        Command(phrases: ["virgola", "comma"], replacement: ",", attachesToPreviousWord: true, requiresContext: true),
        // Runs LAST: by now every multi-word "punto ..." keyword has been
        // consumed, so what remains is the bare noun/command ambiguity.
        Command(phrases: ["punto", "period", "full stop"], replacement: ".", attachesToPreviousWord: true, requiresContext: true)
    ]

    /// Words that, immediately AFTER a bare command word, mean it was the
    /// ordinary noun and not a command: "punto di vista", "punto e mezzo".
    /// Only consulted when a plain space follows the word: after engine
    /// punctuation ("punto, e poi") the next word starts a new thought.
    private static let nonCommandFollowers: Set<String> = [
        "di", "e", "ed", "sul", "sulla", "della", "del", "dai", "degli", "dei",
        "of", "and", "on", "in", "at", "for", "to"
    ]

    /// Numbers after the word make it an item label, not a full stop:
    /// agenda and list numbering ("punto due", "punto 3") and decimals
    /// ("tre virgola cinque"). Digits are matched separately.
    private static let numberFollowers: Set<String> = [
        "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto",
        "nove", "dieci", "undici", "dodici", "tredici", "quattordici",
        "quindici", "sedici", "diciassette", "diciotto", "diciannove", "venti"
    ]

    /// Ordinals label an item only when the word OPENS the clause
    /// ("Punto primo: il bilancio"). Mid-sentence they are what the user
    /// dictates next ("prima frase punto secondo paragrafo"), so there the
    /// word stays a command.
    private static let ordinalFollowers: Set<String> = [
        "primo", "secondo", "terzo", "quarto", "quinto", "sesto", "settimo",
        "ottavo", "nono", "decimo", "ultimo"
    ]

    /// Words that, immediately BEFORE a bare command word, mean it was
    /// governed by a determiner or preposition: "un punto", "il punto di
    /// partenza", "a un certo punto". Elided forms ("l'", "un'", "dell'")
    /// arrive split at the apostrophe, as "l", "un", "dell".
    /// No English "i": the pronoun "I" would read as the Italian article.
    private static let nonCommandPredecessors: Set<String> = [
        "un", "uno", "una", "il", "lo", "la", "gli", "le", "l",
        "quel", "quella", "quelli", "quelle", "quell", "questo", "questa", "questi",
        "queste", "qual", "quale", "ciascun", "ciascuna", "ogni",
        "di", "del", "della", "dei", "degli", "delle", "dell", "dal", "dalla", "dai",
        "dalle", "dall", "a", "al", "alla", "ai", "agli", "alle", "all", "in", "nel",
        "nella", "nei", "negli", "nelle", "nell", "su", "sul", "sulla", "sui", "sugli",
        "sulle", "sull", "per", "tra", "fra", "con", "col", "da", "senza",
        "the", "an", "this", "that", "these", "those", "my", "your", "his",
        "her", "our", "their", "its", "one", "some", "any", "each", "every",
        "next", "last", "first", "second", "third", "same", "single",
        "of", "on", "at", "for", "to", "from", "with", "without", "about"
    ]

    /// Adjectives that sit between a determiner and the noun: "il primo
    /// punto", "un altro punto", "l'ultimo punto". Only these count — a
    /// generic "determiner two words back" rule would swallow real commands
    /// like "ho visto il film punto".
    private static let prenominalAdjectives: Set<String> = [
        "primo", "prima", "secondo", "seconda", "terzo", "terza", "ultimo",
        "ultima", "altro", "altra", "stesso", "stessa", "nuovo", "nuova",
        "unico", "unica", "solo", "sola", "singolo", "vero", "vera",
        "buon", "buono", "buona", "bel", "bello", "bella", "piccolo",
        "piccola", "grande", "gran", "certo", "certa", "preciso", "precisa",
        "ogni", "qualche"
    ]

    /// Two-word prefixes that also introduce the noun: "un certo punto",
    /// "di un punto". Checked when the single preceding word is ambiguous.
    private static let nonCommandPredecessorPhrases: Set<String> = [
        "un certo", "una certa", "un qualsiasi", "quel certo", "di un", "di una",
        "a un", "ad un", "in un", "in una", "da un", "da una", "per un", "per una",
        "lo stesso", "a quel", "a questa", "in quel", "in questa"
    ]

    public static func apply(to text: String) -> String {
        var result = text

        for command in commands {
            for phrase in command.phrases {
                result = replace(
                    phrase,
                    with: command.replacement,
                    attachesToPreviousWord: command.attachesToPreviousWord,
                    requiresContext: command.requiresContext,
                    in: result
                )
            }
        }

        return cleanUp(result)
    }

    /// Replaces whole-word occurrences of `phrase`. With `requiresContext`,
    /// an occurrence is skipped unless the surrounding words show it was
    /// spoken as a command — this is what keeps "a un certo punto" and
    /// "punto di vista" intact while "prima frase punto seconda frase" still
    /// punctuates.
    private static func replace(
        _ phrase: String,
        with replacement: String,
        attachesToPreviousWord: Bool,
        requiresContext: Bool,
        in text: String
    ) -> String {
        let pattern = "(?i)(^|\\s|\\n)(" + NSRegularExpression.escapedPattern(for: phrase) + ")(?=[\\s.,;:!?]|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex

        for match in matches {
            // Group 0 is the whole match, 1 the leading separator, 2 the word.
            guard
                let leadRange = Range(match.range(at: 1), in: text),
                let wordRange = Range(match.range(at: 2), in: text)
            else { continue }

            if requiresContext, !isCommandOccurrence(
                in: text,
                leadRange: leadRange,
                wordRange: wordRange
            ) {
                continue
            }

            result += text[cursor..<leadRange.lowerBound]
            if !attachesToPreviousWord {
                result += text[leadRange]
            }
            result += replacement
            cursor = wordRange.upperBound
        }

        result += text[cursor...]
        return result
    }

    /// Decides whether a bare command word was spoken as a command. It was
    /// NOT when a determiner/preposition governs it, when a word that
    /// continues the ordinary noun follows it, or when a number labels it.
    /// Those checks run first — even when punctuation follows, because the
    /// engine punctuates prose too ("a un certo punto, ho deciso").
    /// Everything else counts as a command: the user saying "punto" and
    /// nothing else means the end of a sentence, and that is the common case.
    private static func isCommandOccurrence(
        in text: String,
        leadRange: Range<String.Index>,
        wordRange: Range<String.Index>
    ) -> Bool {
        let before = text[..<leadRange.lowerBound]

        // A determiner or preposition governs it: "un punto", "a un certo
        // punto", "il punto di partenza", "l'ultimo punto".
        let previous = lastWords(in: before, count: 2)
        if let immediatePrevious = previous.first {
            if nonCommandPredecessors.contains(immediatePrevious) { return false }
            if previous.count == 2 {
                if nonCommandPredecessorPhrases.contains(previous[1] + " " + previous[0]) {
                    return false
                }
                if prenominalAdjectives.contains(previous[0]),
                   nonCommandPredecessors.contains(previous[1]) {
                    return false
                }
            }
        }

        // Punctuation or end-of-line directly after ("punto," / "punto\n"):
        // nothing continues the noun, so the word closed the thought.
        if let immediate = text[wordRange.upperBound...].first,
           immediate.isPunctuation || immediate.isNewline {
            return true
        }

        if let follower = firstWord(after: wordRange.upperBound, in: text) {
            // A following word that continues the ordinary noun: "punto di".
            if nonCommandFollowers.contains(follower) { return false }
            // An item label or a decimal: "punto due", "punto 3",
            // "tre virgola cinque".
            if numberFollowers.contains(follower) { return false }
            if follower.first?.isNumber == true { return false }
            // "Punto primo: …" opening a clause is a heading, not a stop.
            if ordinalFollowers.contains(follower), opensClause(before) { return false }
        }

        return true
    }

    /// True when nothing but whitespace separates `before` from the start of
    /// the text, a line, or a sentence.
    private static func opensClause(_ before: Substring) -> Bool {
        guard let last = before.last(where: { !($0.isWhitespace && !$0.isNewline) }) else {
            return true
        }
        return last.isNewline || ".!?:;".contains(last)
    }

    /// The first word after `index`, lowercased. Nil at end of text.
    private static func firstWord(after index: String.Index, in text: String) -> String? {
        let tail = text[index...]
        guard let start = tail.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        var end = start
        while end < tail.endIndex, !tail[end].isWhitespace, !tail[end].isPunctuation {
            end = tail.index(after: end)
        }
        guard start < end else { return nil }
        return String(tail[start..<end]).lowercased()
    }

    /// Up to `count` trailing words, lowercased and stripped of
    /// punctuation, nearest first. Elisions are split at the apostrophe so
    /// "l'ultimo" reads as "l" + "ultimo".
    private static func lastWords(in text: Substring, count: Int) -> [String] {
        let apostrophes: Set<Character> = ["'", "\u{2019}"]
        let words = text
            .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            .suffix(count)
            .flatMap { $0.split(omittingEmptySubsequences: true, whereSeparator: { apostrophes.contains($0) }) }
            .map { word in
                word
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
                    .lowercased()
            }
            .filter { !$0.isEmpty }
        return Array(words.suffix(count).reversed())
    }

    private static func regexReplace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    /// Fixes artifacts the substitutions leave behind: stray punctuation
    /// spacing, duplicate marks from engine+command, spaces around breaks,
    /// missing capitalization after sentence-ending marks and breaks.
    /// Deliberately never inserts characters between two non-space characters
    /// — "example.com", "3.5" and e-mail addresses must survive untouched.
    private static func cleanUp(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "[ \\t]+([.,;:!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([.,;:!?])[.,]+", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        result = capitalizeSentenceStarts(result)
        return result
    }

    /// Capitalizes the first letter of the text, of every line, and of every
    /// word that follows a sentence-ending mark **plus whitespace**. The
    /// whitespace requirement keeps URLs, e-mail addresses and decimals
    /// ("example.com", "3.5") intact.
    private static func capitalizeSentenceStarts(_ text: String) -> String {
        var characters = Array(text)
        var armed = true
        var pendingEnder = false
        for index in characters.indices {
            let character = characters[index]
            if character == "\n" {
                armed = true
                pendingEnder = false
            } else if character.isWhitespace {
                if pendingEnder {
                    armed = true
                    pendingEnder = false
                }
            } else if character == "." || character == "!" || character == "?" {
                pendingEnder = true
            } else if character.isLetter {
                if armed {
                    characters[index] = Character(character.uppercased())
                    armed = false
                }
                pendingEnder = false
            } else {
                armed = false
                pendingEnder = false
            }
        }
        return String(characters)
    }
}
