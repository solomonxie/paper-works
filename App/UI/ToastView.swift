import SwiftUI

/// One line, one action: dark pill. The host decides placement and the 5s timer.
struct ToastView: View {
    let message: String
    var onUndo: (() -> Void)?
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Space.md) {
            Text(message).font(TypeStyle.body).foregroundStyle(scheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onUndo {
                Button("Undo", action: onUndo)
                    .font(TypeStyle.label.weight(.semibold))
                    .foregroundStyle(scheme == .dark ? Palette.light.accent : Palette.dark.accent)
            }
        }
        .padding(.vertical, Space.md).padding(.horizontal, Space.lg)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(p.text))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
