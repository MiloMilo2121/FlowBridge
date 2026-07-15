import Foundation

/// The user's personal vocabulary: proper nouns, brand names, domain jargon.
///
/// This is the feature Apple's dictation and the iOS 26 SpeechTranscriber
/// both lack. Terms are injected as a Whisper prompt bias and as
/// `contextualStrings` for `DictationTranscriber`, and are available to the
/// polisher as a correction dictionary. Stored in the App Group so the
/// keyboard can read them too.
public final class VocabularyStore: @unchecked Sendable {
    public static let maxTerms = 300

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) throws {
        self.defaults = try defaults ?? SharedContainer.userDefaults()
    }

    public func terms() -> [String] {
        guard let data = defaults.data(forKey: FlowBridgeConstants.vocabularyKey),
              let terms = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return terms
    }

    public func add(_ term: String) throws {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var current = terms()
        guard !current.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        current.append(trimmed)
        if current.count > Self.maxTerms {
            current.removeFirst(current.count - Self.maxTerms)
        }
        try save(current)
    }

    public func remove(_ term: String) throws {
        var current = terms()
        current.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        try save(current)
    }

    /// Renames one saved term without changing its position in the user's
    /// vocabulary. Renaming to an existing term merges the duplicate rather
    /// than leaving two spellings that would compete in the recognition bias.
    public func replace(_ original: String, with replacement: String) throws {
        let trimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var current = terms()
        guard let originalIndex = current.firstIndex(where: {
            $0.caseInsensitiveCompare(original) == .orderedSame
        }) else { return }

        if current.indices.contains(where: {
            $0 != originalIndex && current[$0].caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            current.remove(at: originalIndex)
            // Preserve the existing canonical spelling.
        } else {
            current[originalIndex] = trimmed
        }
        try save(current)
    }

    public func replaceAll(_ terms: [String]) throws {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        try save(Array(cleaned.prefix(Self.maxTerms)))
    }

    /// Prompt-bias text for Whisper: a natural sentence listing the terms,
    /// which nudges decoding toward them without constraining it.
    public func promptBiasText() -> String? {
        let terms = terms()
        guard !terms.isEmpty else { return nil }
        return "Glossary: " + terms.joined(separator: ", ") + "."
    }

    private func save(_ terms: [String]) throws {
        let data = try JSONEncoder().encode(terms)
        defaults.set(data, forKey: FlowBridgeConstants.vocabularyKey)
    }
}
