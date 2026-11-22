import Foundation
import PaperWorksCore
import UserNotifications

public enum Permission: String, Sendable {
  case granted, denied, undetermined
}

/// Local reminder notifications. A tap publishes the reminder's target in `opened`.
@MainActor
public final class Notifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  public static let shared = Notifications()

  @Published public private(set) var opened: String?

  private var center: UNUserNotificationCenter { .current() }

  /// Call at launch, before any tap can arrive, so a cold start from a reminder still lands.
  public func install() {
    center.delegate = self
  }

  public func status() async -> Permission {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: return .granted
    case .denied: return .denied
    default: return .undetermined
    }
  }

  public func request() async -> Bool {
    (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
  }

  /// Replaces every pending reminder (at most 64). Returns the number added.
  public func replaceQueue(_ items: [NativeReminder]) async -> Int {
    center.removeAllPendingNotificationRequests()
    var added = 0
    for item in items.prefix(64) {
      guard let request = Self.request(for: item) else { continue }
      if (try? await center.add(request)) != nil { added += 1 }
    }
    return added
  }

  public func pendingCount() async -> Int {
    await center.pendingNotificationRequests().count
  }

  /// Returns the last tapped target once, then clears it.
  public func takeOpened() -> String? {
    defer { opened = nil }
    return opened
  }

  nonisolated public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let target = response.notification.request.content.userInfo["target"] as? String ?? "radar"
    Task { @MainActor in Notifications.shared.opened = target }
    completionHandler()
  }

  nonisolated public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  private static func request(for item: NativeReminder) -> UNNotificationRequest? {
    let components: DateComponents
    let repeats: Bool
    if let weekday = item.weekday {
      components = DateComponents(hour: item.hour, minute: 0, weekday: weekday)
      repeats = true
    } else if let date = item.date, var dated = DateComponents(civilDate: date) {
      dated.hour = item.hour
      dated.minute = 0
      components = dated
      repeats = false
    } else {
      return nil
    }

    let content = UNMutableNotificationContent()
    content.title = item.title
    content.body = item.body
    content.sound = .default
    content.userInfo = ["target": item.target]
    content.threadIdentifier = "paper-works"

    return UNNotificationRequest(
      identifier: item.id,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
  }
}
