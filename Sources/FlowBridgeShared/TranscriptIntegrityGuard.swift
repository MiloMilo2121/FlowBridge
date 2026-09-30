import Foundation

/// A cleanup may remove fillers and immediate repeated words, and adjust
/// ordinary punctuation/case. It cannot replace words or alter figures.
public enum TranscriptIntegrityGuard {
    private static let fillers: Set<String> = [
        "ehm", "em", "um", "uh", "erm", "mmm", "cioè"
    ]
    private static let protected = CharacterSet(charactersIn: "?!€$%+-")

    public static func accepts(original: String, cleaned: String) -> Bool {
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard numbers(original) == numbers(cleaned) else { return false }
        guard symbols(original) == symbols(cleaned) else { return false }
        let before = words(original)
        let after = words(cleaned)
        var index = 0
        for (offset, word) in before.enumerated() {
            if index < after.count, word == after[index] {
                index += 1
            } else if fillers.contains(word) || (offset > 0 && word == before[offset - 1]) {
                continue
            } else {
                return false
            }
        }
        return index == after.count
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func numbers(_ text: String) -> [String] {
        matches(#"\d+(?:[.,]\d+)*"#, in: text)
    }

    private static func words(_ text: String) -> [String] {
        matches(#"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?"#, in: text)
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
    }

    private static func symbols(_ text: String) -> String {
        String(text.unicodeScalars.filter { protected.contains($0) })
    }
}
