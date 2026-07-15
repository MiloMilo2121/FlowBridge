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

    var activityKind: DictationActivityAttributes.ContentState.SuggestedActionKind {
        switch self {
        case .calendarEvent: return .calendar
        case .reminder: return .reminder
        case .message: return .message
        case .email: return .email
        }
    }

    /// A verb belongs on a system control; the in-app Action Bar can keep
    /// the noun label because it has more explanatory space.
    var activityTitle: String {
        switch self {
        case .calendarEvent: return "Add event"
        case .reminder: return "Add reminder"
        case .message: return "Open Messages"
        case .email: return "Open Mail"
        }
    }

    /// Message and Mail are hand-offs: FlowBridge can truthfully record that
    /// it opened a filled composer, but cannot claim the user sent it.
    var handoffHistoryLabel: String {
        switch self {
        case .message: return "Opened Messages"
        case .email: return "Opened Mail"
        case .calendarEvent: return "Opened Calendar"
        case .reminder: return "Opened Reminders"
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
///
/// Session lifecycle mirrors `TranscriptPolisher`: any optional warmup is
/// idle-only, and `classify` consumes and clears it. Reusing one session
/// across takes would grow its conversation history forever, since each
/// `respond` call adds to it.
actor IntentClassifier {
    static let shared = IntentClassifier()

    /// Beyond this length it's prose being dictated, not a command.
    private static let maxWords = 120
    private static let responseBudget: Duration = .seconds(8)

#if canImport(FoundationModels)
    private var session: LanguageModelSession?

    func prewarm() {
        guard SystemLanguageModel.default.availability == .available else { return }
        if session == nil {
            session = LanguageModelSession(instructions: Self.instructions)
        }
        session?.prewarm()
    }

    func releaseSession() {
        session = nil
    }
#else
    func prewarm() {}
    func releaseSession() {}
#endif

    func classify(_ text: String, now: Date = Date()) async -> SuggestedAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // A labeled conversation is a recording of other people, not an
        // instruction from the speaker.
        guard SpeakerTranscriptFormatter.turns(in: trimmed) == nil else { return nil }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard (2...Self.maxWords).contains(wordCount) else { return nil }

#if canImport(FoundationModels)
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let activeSession = session ?? LanguageModelSession(instructions: Self.instructions)
        session = nil
        FBLog.log("actions: classify begin (budget=8s)")
        let inference = Task<ParsedClassification?, Never> {
            do {
                let response = try await activeSession.respond(
                    to: trimmed,
                    generating: Classification.self,
                    options: GenerationOptions(sampling: .greedy)
                )
                return ParsedClassification(
                    category: response.content.category,
                    title: response.content.title,
                    content: response.content.content
                )
            } catch {
                return nil
            }
        }
        let outcome = await TaskDeadline.value(
            from: inference,
            fallback: nil,
            after: Self.responseBudget
        )
        guard let classification = outcome.value else {
            FBLog.log(outcome.timedOut
                ? "actions: classify timed out"
                : "actions: classify unavailable")
            return nil
        }

        let fallbackTitle = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(6).joined(separator: " ")
        // Generated strings cross into EventKit and system URL composers.
        // Keep that trust boundary narrow even if the guided model ignores
        // its prompt: one-line titles and bounded bodies only.
        let bestTitle = Self.boundedTitle(classification.title, fallback: fallbackTitle)
        // The composer body: the command wrapper ("send Sarah a message
        // saying…") stripped, just what was meant to be said. Falls back to
        // the full dictation if the model returns nothing usable — a
        // slightly redundant body beats a missing one.
        let content = classification.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let bestBody = Self.boundedBody(content.isEmpty ? trimmed : content)
        let date = Self.firstFutureDate(in: trimmed, after: now)

        switch classification.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
            return .message(body: bestBody)
        case "email":
            return .email(subject: bestTitle, body: bestBody)
        default:
            return nil
        }
#else
        return nil
#endif
    }

    private static func boundedTitle(_ generated: String, fallback: String) -> String {
        let collapsed = generated
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let candidate = collapsed.isEmpty ? fallback : collapsed
        return String(candidate.prefix(96))
    }

    private static func boundedBody(_ generated: String) -> String {
        String(generated.prefix(4_000))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

#if canImport(FoundationModels)
    private struct ParsedClassification: Sendable {
        let category: String
        let title: String
        let content: String
    }

    // Not `private`: the @Generable macro expands to an extension that can't
    // see a private nested type.
    @Generable
    struct Classification {
        @Guide(description: "The single best category: 'calendar' when the dictation describes a meeting, appointment or plan happening at a day or time; 'reminder' when it is a task, errand or shopping list to remember; 'message' when the speaker asks to send or text this to someone; 'email' when it is or asks for an email; otherwise 'dictation'. When unsure, 'dictation'.")
        var category: String

        @Guide(description: "A very short title for the event, reminder or email (at most 8 words), in the exact same language as the dictation. Empty when the category is 'dictation'.")
        var title: String

        @Guide(description: "Only for 'message' or 'email': the actual message to send, with the command wrapper removed — e.g. 'send Sarah a message saying I'll be late' becomes just 'I'll be late'. Verbatim otherwise, same language, no added content. Empty for other categories.")
        var content: String
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
