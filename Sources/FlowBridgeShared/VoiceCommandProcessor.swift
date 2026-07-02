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
    private static func cleanUp(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "[ \\t]+([.,;:!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([.,;:!?])[.,]+", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "([.,;:!?])(\\p{L})", with: "$1 $2", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        result = capitalizeSentenceStarts(result)
        return result
    }

    private static func capitalizeSentenceStarts(_ text: String) -> String {
        var characters = Array(text)
        var capitalizeNext = true
        for index in characters.indices {
            let character = characters[index]
            if capitalizeNext, character.isLetter {
                characters[index] = Character(character.uppercased())
                capitalizeNext = false
            } else if character == "." || character == "!" || character == "?" || character == "\n" {
                capitalizeNext = true
            } else if character.isLetter {
                capitalizeNext = false
            }
        }
        return String(characters)
    }
}
