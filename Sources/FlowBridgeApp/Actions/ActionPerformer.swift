import EventKit
import Foundation
import UIKit

/// Executes a `SuggestedAction`. Calendar and reminders go straight into
/// EventKit (write-only calendar access — FlowBridge never reads the user's
/// agenda); message and email open the system composer with the text
/// prefilled. Permission is requested lazily, at the moment of the tap.
@MainActor
final class ActionPerformer {
    static let shared = ActionPerformer()

    enum Outcome {
        /// Created in place — show the confirmation.
        case done(String)
        /// Handed off to another app's composer — nothing left to confirm.
        case openedApp
        case failed(String)
    }

    private let eventStore = EKEventStore()

    func perform(_ action: SuggestedAction) async -> Outcome {
        switch action {
        case .calendarEvent(let title, let start):
            return await addCalendarEvent(title: title, start: start)
        case .reminder(let title, let due):
            return await addReminder(title: title, due: due)
        case .message(let body):
            return await open(scheme: "sms:&body=", payload: body, failure: "Couldn't open Messages")
        case .email(let subject, let body):
            var components = URLComponents()
            components.scheme = "mailto"
            components.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            // No canOpenURL pre-check: querying sms/mailto needs an
            // LSApplicationQueriesSchemes entry; open() itself doesn't.
            guard let url = components.url else {
                return .failed("No mail app configured")
            }
            guard await UIApplication.shared.open(url) else {
                return .failed("No mail app configured")
            }
            return .openedApp
        }
    }

    private func addCalendarEvent(title: String, start: Date) async -> Outcome {
        do {
            guard try await eventStore.requestWriteOnlyAccessToEvents() else {
                return .failed("Calendar access denied — enable it in Settings")
            }
        } catch {
            return .failed("Calendar access failed")
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        do {
            try eventStore.save(event, span: .thisEvent)
            FBLog.log("actions: calendar event created")
            return .done("Added to Calendar")
        } catch {
            FBLog.log("actions: calendar save failed: \(error.localizedDescription)")
            return .failed("Couldn't save the event")
        }
    }

    private func addReminder(title: String, due: Date?) async -> Outcome {
        do {
            guard try await eventStore.requestFullAccessToReminders() else {
                return .failed("Reminders access denied — enable it in Settings")
            }
        } catch {
            return .failed("Reminders access failed")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        }
        do {
            try eventStore.save(reminder, commit: true)
            FBLog.log("actions: reminder created")
            return .done("Added to Reminders")
        } catch {
            FBLog.log("actions: reminder save failed: \(error.localizedDescription)")
            return .failed("Couldn't save the reminder")
        }
    }

    /// `sms:` predates URL components — the body rides after a bare `&`.
    private func open(scheme: String, payload: String, failure: String) async -> Outcome {
        // Strict encoding: a literal &, = or ? inside the dictated text would
        // otherwise terminate the body parameter.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        let encoded = payload.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: scheme + encoded) else {
            return .failed(failure)
        }
        guard await UIApplication.shared.open(url) else {
            return .failed(failure)
        }
        return .openedApp
    }
}
