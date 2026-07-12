import FlowBridgeShared
import Foundation
import UIKit

/// Post-dictation vocabulary mining: words the system dictionary doesn't
/// recognize are usually names, brands or jargon — exactly what the
/// recognition bias needs. Suggestions are offered as one-tap chips; a
/// dismissed word never comes back.
@MainActor
enum VocabularySuggester {
    static func suggestions(from text: String, limit: Int = 3) -> [String] {
        guard !text.isEmpty else { return [] }

        let existing = Set(((try? VocabularyStore())?.terms() ?? []).map { $0.lowercased() })
        let dismissed = dismissedSet()
        let checker = UITextChecker()
        let language = DictationLanguage.current == .english ? "en_US" : "it_IT"

        var found: [String: (display: String, count: Int)] = [:]
        let tokens = text.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        for token in tokens {
            let word = String(token)
            guard word.count >= 4 else { continue }
            let key = word.lowercased()
            guard !existing.contains(key), !dismissed.contains(key) else { continue }

            if var entry = found[key] {
                entry.count += 1
                found[key] = entry
                continue
            }

            let range = NSRange(location: 0, length: word.utf16.count)
            let miss = checker.rangeOfMisspelledWord(
                in: word,
                range: range,
                startingAt: 0,
                wrap: false,
                language: language
            )
            guard miss.location != NSNotFound else { continue }
            found[key] = (word, 1)
        }

        return found.values
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.display < rhs.display
            }
            .prefix(limit)
            .map(\.display)
    }

    static func dismiss(_ word: String) {
        var set = dismissedSet()
        set.insert(word.lowercased())
        let defaults = try? SharedContainer.userDefaults()
        if let data = try? JSONEncoder().encode(Array(set)) {
            defaults?.set(data, forKey: FlowBridgeConstants.vocabularyDismissedKey)
        }
    }

    private static func dismissedSet() -> Set<String> {
        let defaults = try? SharedContainer.userDefaults()
        guard let data = defaults?.data(forKey: FlowBridgeConstants.vocabularyDismissedKey),
              let words = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(words)
    }
}
