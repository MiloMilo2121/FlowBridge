import Foundation

public enum DictationTextNormalizer {
    public static func normalize(_ rawText: String) -> String {
        var text = rawText
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "([\\(\\[\\{])\\s+", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([\\)\\]\\}])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = text.first else { return text }
        text.replaceSubrange(text.startIndex...text.startIndex, with: String(first).uppercased())
        return text
    }
}

