import SwiftUI

enum PWButtonKind { case primary, secondary, plain }

struct PWButtonStyle: ButtonStyle {
    var kind: PWButtonKind = .secondary
    var destructive = false
    @Environment(\.palette) private var p
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = destructive ? p.late : p.accent
        let primary = kind == .primary
        configuration.label
            .font(primary ? TypeStyle.label.weight(.semibold) : TypeStyle.label)
            .foregroundStyle(primary ? p.onAccent : tint)
            .multilineTextAlignment(.center)
            .padding(.vertical, kind == .plain ? 0 : Space.md)
            .padding(.horizontal, kind == .plain ? 0 : Space.lg)
            .frame(minHeight: kind == .plain ? nil : 44)
            .background(background(tint))
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }

    @ViewBuilder private func background(_ tint: Color) -> some View {
        switch kind {
        case .primary: RoundedRectangle(cornerRadius: Radius.md).fill(tint)
        case .secondary: RoundedRectangle(cornerRadius: Radius.md).fill(destructive ? p.lateSoft : p.accentSoft)
        case .plain: Color.clear
        }
    }
}

extension ButtonStyle where Self == PWButtonStyle {
    static var pwPrimary: PWButtonStyle { .init(kind: .primary) }
    static var pwSecondary: PWButtonStyle { .init(kind: .secondary) }
    static var pwPlain: PWButtonStyle { .init(kind: .plain) }
    static func pw(_ kind: PWButtonKind, destructive: Bool = false) -> PWButtonStyle {
        .init(kind: kind, destructive: destructive)
    }
}

/// Convenience: titled button using the styles above.
struct PWButton: View {
    let title: String
    var kind: PWButtonKind = .secondary
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(PWButtonStyle(kind: kind, destructive: destructive))
            .accessibilityLabel(spoken(title))
    }
}
