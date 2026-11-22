import SwiftUI

/// [x] item — a checklist line. Optional › for rows that also go somewhere.
struct CheckRow: View {
    let label: String
    let checked: Bool
    let onToggle: () -> Void
    var onOpen: (() -> Void)?
    var detail: String?
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: Space.sm) {
            Button(action: onToggle) {
                HStack(spacing: Space.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(checked ? p.done : p.faint, lineWidth: 1.5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(checked ? p.done : .clear))
                        if checked { Text("✓").font(.system(size: 14, weight: .bold)).foregroundStyle(p.onAccent) }
                    }
                    .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(TypeStyle.body).foregroundStyle(checked ? p.dim : p.text).lineLimit(2)
                        if let detail { Text(detail).font(TypeStyle.caption).foregroundStyle(p.dim) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityAddTraits(checked ? [.isSelected] : [])
            .accessibilityValue(checked ? "checked" : "unchecked")
            if let onOpen {
                Button(action: onOpen) {
                    Text("›").font(TypeStyle.body).foregroundStyle(p.faint).padding(Space.sm)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(label)")
            }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .frame(minHeight: 48)
    }
}
