import EventKit
import Foundation
import React

/// Copies steps into a Reminders list once. A list with the same name is reused,
/// and titles already in it are skipped, so exporting twice adds only what's new.
@objc(ReminderExport)
class ReminderExport: NSObject {
  @objc static func requiresMainQueueSetup() -> Bool { false }

  private let store = EKEventStore()

  private func access(_ done: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      store.requestFullAccessToReminders { granted, _ in done(granted) }
    } else {
      store.requestAccess(to: .reminder) { granted, _ in done(granted) }
    }
  }

  private func list(_ title: String) -> EKCalendar? {
    if let found = store.calendars(for: .reminder).first(where: { $0.title == title }) { return found }
    let cal = EKCalendar(for: .reminder, eventStore: store)
    cal.title = title
    guard let source = store.defaultCalendarForNewReminders()?.source else { return nil }
    cal.source = source
    do { try store.saveCalendar(cal, commit: true) } catch { return nil }
    return cal
  }

  private func titles(in cal: EKCalendar, _ done: @escaping (Set<String>) -> Void) {
    store.fetchReminders(matching: store.predicateForReminders(in: [cal])) { found in
      done(Set((found ?? []).compactMap(\.title)))
    }
  }

  /// items: [{ title, date: YYYY-MM-DD, notes }]. Resolves the count added, or -1 when access is refused.
  @objc(export:items:resolver:rejecter:)
  func export(
    _ listTitle: String,
    items: [[String: Any]],
    resolver resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    access { granted in
      guard granted else { return resolve(-1) }
      guard let cal = self.list(listTitle) else {
        return reject("REMINDERS", "Couldn't create the list in Reminders", nil)
      }
      self.titles(in: cal) { existing in
        var added = 0
        for item in items {
          guard let t = item["title"] as? String, !existing.contains(t), let d = item["date"] as? String else { continue }
          let p = d.split(separator: "-").compactMap { Int($0) }
          guard p.count == 3 else { continue }
          let reminder = EKReminder(eventStore: self.store)
          reminder.calendar = cal
          reminder.title = t
          reminder.notes = item["notes"] as? String
          reminder.dueDateComponents = DateComponents(calendar: Calendar(identifier: .gregorian), year: p[0], month: p[1], day: p[2])
          if (try? self.store.save(reminder, commit: false)) != nil { added += 1 }
        }
        do { try self.store.commit() } catch {
          return reject("REMINDERS", error.localizedDescription, error)
        }
        resolve(added)
      }
    }
  }
}
