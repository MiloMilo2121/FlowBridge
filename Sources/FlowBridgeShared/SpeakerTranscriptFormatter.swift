import Foundation

/// The user toggle: label speakers in the final transcript when more than
/// one voice is detected. Diarization always happens in the post-stop final
/// pass (cloud Scribe natively, on-device via the local diarizer); the live
/// stream stays unlabeled.
public enum SpeakerDetection {
    public static var isEnabled: Bool {
        let defaults = try? SharedContainer.userDefaults()
        return defaults?.object(forKey: FlowBridgeConstants.speakersEnabledKey) as? Bool ?? false
    }

    public static func set(_ enabled: Bool) {
        let defaults = try? SharedContainer.userDefaults()
        defaults?.set(enabled, forKey: FlowBridgeConstants.speakersEnabledKey)
    }
}

/// Turns diarized words into a labeled conversation transcript — and parses
/// one back into turns for per-turn polishing and speaker renaming.
///
/// Labels are anonymous and positional: "Speaker 1" is whoever spoke first,
/// renameable after the fact (History → Rename speakers). With zero or one
/// distinct speaker the output is flat text, identical to the non-diarized
/// path — labels only appear when they carry information.
public enum SpeakerTranscriptFormatter {
    /// One transcribed word with its time span and the diarizer's raw
    /// speaker identifier ("speaker_0", "A", …). Words must arrive in
    /// transcript order.
    public struct Word: Equatable, Sendable {
        public let text: String
        public let start: TimeInterval
        public let end: TimeInterval
        public let speaker: String

        public init(text: String, start: TimeInterval, end: TimeInterval, speaker: String) {
            self.text = text
            self.start = start
            self.end = end
            self.speaker = speaker
        }
    }

    /// One consecutive run of words by the same speaker.
    public struct Turn: Equatable, Sendable {
        public let label: String
        public var text: String

        public init(label: String, text: String) {
            self.label = label
            self.text = text
        }
    }

    /// A diarizer speech segment (who spoke when), independent of words.
    public struct Segment: Equatable, Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let speaker: String

        public init(start: TimeInterval, end: TimeInterval, speaker: String) {
            self.start = start
            self.end = end
            self.speaker = speaker
        }
    }

    // MARK: - Rendering

    /// Renders diarized words as `"Speaker 1: …\n\nSpeaker 2: …"`, grouping
    /// consecutive same-speaker words into turns and numbering speakers by
    /// first appearance. One distinct speaker → plain flat text.
    public static func labeledText(words: [Word]) -> String {
        let meaningful = words.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !meaningful.isEmpty else { return "" }

        var labelByRawSpeaker: [String: String] = [:]
        var turns: [(label: String, pieces: [String])] = []
        for word in meaningful {
            let label: String
            if let known = labelByRawSpeaker[word.speaker] {
                label = known
            } else {
                label = "Speaker \(labelByRawSpeaker.count + 1)"
                labelByRawSpeaker[word.speaker] = label
            }
            if let last = turns.indices.last, turns[last].label == label {
                turns[last].pieces.append(word.text)
            } else {
                turns.append((label, [word.text]))
            }
        }

        guard labelByRawSpeaker.count > 1 else {
            return DictationTextNormalizer.normalize(meaningful.map(\.text).joined(separator: " "))
        }
        return compose(turns: turns.map {
            Turn(label: $0.label, text: DictationTextNormalizer.normalize($0.pieces.joined(separator: " ")))
        })
    }

    public static func compose(turns: [Turn]) -> String {
        turns.map { "\($0.label): \($0.text)" }.joined(separator: "\n\n")
    }

    // MARK: - Word ↔ segment fusion (on-device path)

    /// Assigns each timed word to the diarizer segment containing its
    /// midpoint, falling back to the nearest segment — a word can never be
    /// dropped by imperfect segment boundaries.
    public static func assign(
        words: [(text: String, start: TimeInterval, end: TimeInterval)],
        to segments: [Segment]
    ) -> [Word] {
        guard !segments.isEmpty else { return [] }
        return words.map { word in
            let midpoint = (word.start + word.end) / 2
            let segment = segments.first { midpoint >= $0.start && midpoint < $0.end }
                ?? segments.min { distance(from: midpoint, to: $0) < distance(from: midpoint, to: $1) }!
            return Word(text: word.text, start: word.start, end: word.end, speaker: segment.speaker)
        }
    }

    private static func distance(from time: TimeInterval, to segment: Segment) -> TimeInterval {
        if time < segment.start { return segment.start - time }
        if time > segment.end { return time - segment.end }
        return 0
    }

    // MARK: - Parsing labeled text back

    /// Parses a labeled transcript into its turns. Returns nil for anything
    /// that is not a labeled transcript: fewer than two turns, or content
    /// before the first label. Turn labels are generic (`Name:` at line
    /// start, ≤30 chars) so renamed transcripts keep parsing.
    public static func turns(in text: String) -> [Turn]? {
        var turns: [Turn] = []
        var current: Turn?
        for line in text.components(separatedBy: "\n") {
            if let (label, rest) = turnOpening(line) {
                if let open = current { turns.append(open) }
                current = Turn(label: label, text: rest)
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                guard var open = current else { return nil }
                open.text += "\n" + trimmed
                current = open
            }
        }
        if let open = current { turns.append(open) }
        return turns.count >= 2 ? turns : nil
    }

    /// Distinct labels in order of first appearance — nil when the text is
    /// not a labeled transcript.
    public static func labels(in text: String) -> [String]? {
        guard let turns = turns(in: text) else { return nil }
        var seen: [String] = []
        for turn in turns where !seen.contains(turn.label) {
            seen.append(turn.label)
        }
        return seen
    }

    /// Rewrites turn labels ("Speaker 1" → "Marco"). Unknown or empty
    /// mappings leave the original label; non-labeled text passes through.
    public static func renamed(_ text: String, mapping: [String: String]) -> String {
        guard let turns = turns(in: text) else { return text }
        return compose(turns: turns.map { turn in
            let newLabel = mapping[turn.label]?.trimmingCharacters(in: .whitespaces)
            guard let newLabel, !newLabel.isEmpty else { return turn }
            return Turn(label: newLabel, text: turn.text)
        })
    }

    private static func turnOpening(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let label = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label.count <= 30 else { return nil }
        let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (label, rest)
    }
}
