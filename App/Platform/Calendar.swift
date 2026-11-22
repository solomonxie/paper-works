import EventKit
import Foundation

/// A dated line for a calendar event or a Reminders item. `date` is YYYY-MM-DD.
public struct DatedEntry: Sendable {
  public var title: String
  public var date: String
  public var notes: String?

  public init(title: String, date: String, notes: String? = nil) {
    self.title = title
    self.date = date
    self.notes = notes
  }
}

extension DateComponents {
  public init?(civilDate text: String) {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    self.init(calendar: Calendar(identifier: .gregorian), year: parts[0], month: parts[1], day: parts[2])
  }
}

/// Mirrors start-by dates into a calendar of the app's own, off by default.
/// Every sync rewrites that calendar; nothing else is touched.
public enum CalendarMirror {
  private static let title = "Paper Works"

  /// Rewrites the calendar with one all-day event per entry. Returns the count written, or -1 when access is refused.
  public static func sync(_ entries: [DatedEntry]) async throws -> Int {
    let store = EKEventStore()
    guard (try? await store.requestFullAccessToEvents()) == true else { return -1 }
    guard let cal = calendar(in: store, create: true) else { throw Failure.calendarUnavailable }

    let from = Date().addingTimeInterval(-86400 * 400)
    let to = Date().addingTimeInterval(86400 * 365 * 4)
    let old = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal]))
    for event in old { try? store.remove(event, span: .thisEvent, commit: false) }

    var written = 0
    for entry in entries {
      guard let components = DateComponents(civilDate: entry.date),
        let day = components.calendar?.date(from: components)
      else { continue }
      let event = EKEvent(eventStore: store)
      event.calendar = cal
      event.title = entry.title
      event.notes = entry.notes
      event.isAllDay = true
      event.startDate = day
      event.endDate = day
      if (try? store.save(event, span: .thisEvent, commit: false)) != nil { written += 1 }
    }
    try store.commit()
    return written
  }

  public static func remove() async {
    let store = EKEventStore()
    guard (try? await store.requestFullAccessToEvents()) == true,
      let cal = calendar(in: store, create: false)
    else { return }
    try? store.removeCalendar(cal, commit: true)
  }

  private static func calendar(in store: EKEventStore, create: Bool) -> EKCalendar? {
    if let found = store.calendars(for: .event).first(where: { $0.title == title }) { return found }
    guard create else { return nil }
    let cal = EKCalendar(for: .event, eventStore: store)
    cal.title = title
    cal.source = store.defaultCalendarForNewEvents?.source
      ?? store.sources.first(where: { $0.sourceType == .local })
    do { try store.saveCalendar(cal, commit: true) } catch { return nil }
    return cal
  }

  public enum Failure: LocalizedError {
    case calendarUnavailable

    public var errorDescription: String? {
      switch self {
      case .calendarUnavailable: "Couldn't create the Paper Works calendar"
      }
    }
  }
}
