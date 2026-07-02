import Foundation

/// Computes word error rate between a reference transcript and a hypothesis.
/// Tokenization is deliberately aggressive (case- and punctuation-insensitive)
/// so the metric tracks recognition quality, not normalizer formatting.
public enum WERCalculator {
    public struct Result: Equatable, Sendable {
        public let substitutions: Int
        public let insertions: Int
        public let deletions: Int
        public let referenceWordCount: Int
        public let hypothesisWordCount: Int

        public var errorCount: Int {
            substitutions + insertions + deletions
        }

        /// WER = (S + I + D) / N. An empty reference with a non-empty
        /// hypothesis counts every hypothesis word as an insertion error.
        public var errorRate: Double {
            if referenceWordCount == 0 {
                return hypothesisWordCount == 0 ? 0 : 1
            }
            return Double(errorCount) / Double(referenceWordCount)
        }
    }

    public static func tokens(from text: String) -> [String] {
        let apostropheNormalized = text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()

        var tokens: [String] = []
        var current = ""
        for scalar in apostropheNormalized.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    public static func evaluate(reference: String, hypothesis: String) -> Result {
        let ref = tokens(from: reference)
        let hyp = tokens(from: hypothesis)
        return align(reference: ref, hypothesis: hyp)
    }

    static func align(reference: [String], hypothesis: [String]) -> Result {
        struct Cell {
            var cost: Int
            var substitutions: Int
            var insertions: Int
            var deletions: Int
        }

        let rows = reference.count + 1
        let columns = hypothesis.count + 1
        var previous = [Cell](repeating: Cell(cost: 0, substitutions: 0, insertions: 0, deletions: 0), count: columns)
        var current = previous

        for column in 1..<columns {
            previous[column] = Cell(cost: column, substitutions: 0, insertions: column, deletions: 0)
        }

        for row in 1..<rows {
            current[0] = Cell(cost: row, substitutions: 0, insertions: 0, deletions: row)
            for column in 1..<columns {
                if reference[row - 1] == hypothesis[column - 1] {
                    current[column] = previous[column - 1]
                    continue
                }

                let substitution = previous[column - 1]
                let deletion = previous[column]
                let insertion = current[column - 1]

                if substitution.cost <= deletion.cost, substitution.cost <= insertion.cost {
                    current[column] = Cell(
                        cost: substitution.cost + 1,
                        substitutions: substitution.substitutions + 1,
                        insertions: substitution.insertions,
                        deletions: substitution.deletions
                    )
                } else if deletion.cost <= insertion.cost {
                    current[column] = Cell(
                        cost: deletion.cost + 1,
                        substitutions: deletion.substitutions,
                        insertions: deletion.insertions,
                        deletions: deletion.deletions + 1
                    )
                } else {
                    current[column] = Cell(
                        cost: insertion.cost + 1,
                        substitutions: insertion.substitutions,
                        insertions: insertion.insertions + 1,
                        deletions: insertion.deletions
                    )
                }
            }
            swap(&previous, &current)
        }

        let final = previous[columns - 1]
        return Result(
            substitutions: final.substitutions,
            insertions: final.insertions,
            deletions: final.deletions,
            referenceWordCount: reference.count,
            hypothesisWordCount: hypothesis.count
        )
    }
}
