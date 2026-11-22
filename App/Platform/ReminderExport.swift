import EventKit
import Foundation

/// Copies steps into a Reminders list once. A list with the same name is reused,
/// and titles already in it are skipped, so exporting twice adds only what's new.
public enum ReminderExport {
  /// Returns the count added, or -1 when Reminders access is refused.
  public static func export(_ listTitle: String, items: [DatedEntry]) async throws -> Int {
    let store = EKEventStore()
    guard (try? await store.requestFullAccessToReminders()) == true else { return -1 }
    guard let cal = list(listTitle, in: store) else { throw Failure.listUnavailable }

    let existing = await titles(in: cal, store: store)
    var added = 0
    for item in items where !existing.contains(item.title) {
      guard let due = DateComponents(civilDate: item.date) else { continue }
      let reminder = EKReminder(eventStore: store)
      reminder.calendar = cal
      reminder.title = item.title
      reminder.notes = item.notes
      reminder.dueDateComponents = due
      if (try? store.save(reminder, commit: false)) != nil { added += 1 }
    }
    try store.commit()
    return added
  }

  private static func list(_ title: String, in store: EKEventStore) -> EKCalendar? {
    if let found = store.calendars(for: .reminder).first(where: { $0.title == title }) { return found }
    guard let source = store.defaultCalendarForNewReminders()?.source else { return nil }
    let cal = EKCalendar(for: .reminder, eventStore: store)
    cal.title = title
    cal.source = source
    do { try store.saveCalendar(cal, commit: true) } catch { return nil }
    return cal
  }

  private static func titles(in cal: EKCalendar, store: EKEventStore) async -> Set<String> {
    await withCheckedContinuation { continuation in
      store.fetchReminders(matching: store.predicateForReminders(in: [cal])) { found in
        continuation.resume(returning: Set((found ?? []).compactMap(\.title)))
      }
    }
  }

  public enum Failure: LocalizedError {
    case listUnavailable

    public var errorDescription: String? {
      switch self {
      case .listUnavailable: "Couldn't create the list in Reminders"
      }
    }
  }
}
