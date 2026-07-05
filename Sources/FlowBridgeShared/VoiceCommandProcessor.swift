import Foundation

/// The six essential spoken commands, applied as deterministic text
/// replacements on the final transcript — instant and predictable, never an
/// LLM interpretation. Italian and English, matched as whole words the
/// engine transcribed (case-insensitive).
///
/// Scope is deliberately tiny ("poche cose fatte bene"): punctuation marks,
/// line breaks, paragraph breaks. Anything richer belongs to the polisher.
public enum VoiceCommandProcessor {
    private struct Command {
        let phrases: [String]
        let replacement: String
        /// Punctuation attaches to the previous word; breaks stand alone.
        let attachesToPreviousWord: Bool
    }

    private static let commands: [Command] = [
        // Order matters: longer phrases first so "punto interrogativo" wins
        // over "punto".
        Command(phrases: ["punto interrogativo", "question mark"], replacement: "?", attachesToPreviousWord: true),
        Command(phrases: ["punto esclamativo", "exclamation mark", "exclamation point"], replacement: "!", attachesToPreviousWord: true),
        Command(phrases: ["punto e virgola", "semicolon"], replacement: ";", attachesToPreviousWord: true),
        Command(phrases: ["nuovo paragrafo", "new paragraph"], replacement: "\n\n", attachesToPreviousWord: false),
        Command(phrases: ["a capo", "new line"], replacement: "\n", attachesToPreviousWord: false),
        Command(phrases: ["due punti", "colon"], replacement: ":", attachesToPreviousWord: true),
        Command(phrases: ["virgola", "comma"], replacement: ",", attachesToPreviousWord: true),
        Command(phrases: ["punto", "period", "full stop"], replacement: ".", attachesToPreviousWord: true)
    ]

    public static func apply(to text: String) -> String {
        var result = text

        for command in commands {
            for phrase in command.phrases {
                let pattern = "(?i)(^|\\s)" + NSRegularExpression.escapedPattern(for: phrase) + "(?=[\\s.,;:!?]|$)"
                let replacement: String
                if command.attachesToPreviousWord {
                    replacement = NSRegularExpression.escapedTemplate(for: command.replacement)
                } else {
                    replacement = "$1" + NSRegularExpression.escapedTemplate(for: command.replacement)
                }
                result = regexReplace(result, pattern: pattern, template: replacement)
            }
        }

        return cleanUp(result)
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
