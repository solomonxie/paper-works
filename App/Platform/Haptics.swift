import UIKit

public enum HapticKind: String, Sendable {
  case success, warning, light, medium, selection
}

public enum Haptics {
  /// Follows Settings → Haptics.
  @MainActor public static var enabled = true

  @MainActor
  public static func play(_ kind: HapticKind = .light) {
    guard enabled else { return }
    switch kind {
    case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
    case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
    case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case .selection: UISelectionFeedbackGenerator().selectionChanged()
    case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
  }
}
