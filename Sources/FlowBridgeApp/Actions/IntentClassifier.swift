import FlowBridgeShared
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// What a dictation can become with one tap. The transcript itself is always
/// delivered first (clipboard, history, reveal) — a suggestion is a bonus on
/// top, never a gate.
enum SuggestedAction: Equatable, Sendable {
    case calendarEvent(title: String, start: Date)
    case reminder(title: String, due: Date?)
    case message(body: String)
    case email(subject: String, body: String)

    var label: String {
        switch self {
        case .calendarEvent: return "Calendar Event"
        case .reminder: return "Reminder"
        case .message: return "Message"
        case .email: return "Email"
        }
    }

    var symbol: String {
        switch self {
        case .calendarEvent: return "calendar.badge.plus"
        case .reminder: return "checklist"
        case .message: return "message"
        case .email: return "envelope"
        }
    }

    /// The short human title shown next to the label ("Lunch with Luca").
    var detail: String {
        switch self {
        case .calendarEvent(let title, _): return title
        case .reminder(let title, _): return title
        case .message, .email: return ""
        }
    }
}

/// On-device intent detection over the delivered transcript: the ~3B model
/// picks the category, `NSDataDetector` (locale-aware, deterministic) owns
/// the date. Hybrid on purpose — a small LLM is good at "is this a todo or
/// an appointment?" and bad at absolute datetime math.
///
/// Rules, in order:
/// 1. Never wrong loudly: when unsure the answer is `nil` and the UI shows
///    plain text, exactly as before this feature existed.
/// 2. Runs after delivery, cancellable, off the critical path.
/// 3. On-device only, like the polisher — no text leaves the phone.
enum IntentClassifier {
    /// Beyond this length it's prose being dictated, not a command.
    private static let maxWords = 120

    static func classify(_ text: String, now: Date = Date()) async -> SuggestedAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A labeled conversation is a recording of other people, not an
        // instruction from the speaker.
        guard SpeakerTranscriptFormatter.turns(in: trimmed) == nil else { return nil }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard (2...maxWords).contains(wordCount) else { return nil }

#if canImport(FoundationModels)
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let session = LanguageModelSession(instructions: Self.instructions)
        let classification: Classification
        do {
            let response = try await session.respond(
                to: trimmed,
                generating: Classification.self,
                options: GenerationOptions(sampling: .greedy)
            )
            classification = response.content
        } catch {
            return nil
        }

        let title = classification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(6).joined(separator: " ")
        let bestTitle = title.isEmpty ? fallbackTitle : title
        let date = firstFutureDate(in: trimmed, after: now)

        switch classification.category.lowercased() {
        case "calendar":
            // An event needs a moment in time; without one it degrades to
            // the todo it actually is.
            if let date {
                return .calendarEvent(title: bestTitle, start: date)
            }
            return .reminder(title: bestTitle, due: nil)
        case "reminder":
            return .reminder(title: bestTitle, due: date)
        case "message":
            return .message(body: trimmed)
        case "email":
            return .email(subject: bestTitle, body: trimmed)
        default:
            return nil
        }
#else
        return nil
#endif
    }

#if canImport(FoundationModels)
    // Not `private`: the @Generable macro expands to an extension that can't
    // see a private nested type.
    @Generable
    struct Classification {
        @Guide(description: "The single best category: 'calendar' when the dictation describes a meeting, appointment or plan happening at a day or time; 'reminder' when it is a task, errand or shopping list to remember; 'message' when the speaker asks to send or text this to someone; 'email' when it is or asks for an email; otherwise 'dictation'. When unsure, 'dictation'.")
        var category: String

        @Guide(description: "A very short title for the event, reminder or email (at most 8 words), in the exact same language as the dictation. Empty when the category is 'dictation'.")
        var title: String
    }

    private static let instructions = """
    You label voice dictations so an iPhone can offer a one-tap action. \
    Classify the dictation and give it a short title. Most dictations are \
    plain text (notes, thoughts, prose) — only pick an action category when \
    the dictation clearly is one. Never invent details that are not spoken.
    """
#endif

    /// The first date data-detectors find that lies in the future — "domani
    /// all'una", "Friday 9am". Past references never become events.
    private static func firstFutureDate(in text: String, after now: Date) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.compactMap(\.date).first { $0 > now }
    }
}
