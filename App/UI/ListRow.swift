import SwiftUI

private struct RowPressStyle: ButtonStyle {
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? p.hairline : .clear)
    }
}

/// Label on the left, value on the right, › when it goes somewhere.
struct ListRow<Right: View>: View {
    enum Tone { case normal, accent, late, dim }

    let label: String
    var value: String?
    var detail: String?
    var onPress: (() -> Void)?
    var chevron: Bool
    /// For in-place unfolding rows: › becomes ⌄.
    var open: Bool?
    var tone: Tone = .normal
    var selected = false
    var accessibilityLabelOverride: String?
    @ViewBuilder var right: Right
    @Environment(\.palette) private var p

    init(_ label: String, value: String? = nil, detail: String? = nil, onPress: (() -> Void)? = nil,
         chevron: Bool? = nil, open: Bool? = nil, tone: Tone = .normal, selected: Bool = false,
         accessibilityLabel: String? = nil, @ViewBuilder right: () -> Right) {
        self.label = label; self.value = value; self.detail = detail; self.onPress = onPress
        self.chevron = chevron ?? (onPress != nil); self.open = open; self.tone = tone; self.selected = selected
        self.accessibilityLabelOverride = accessibilityLabel; self.right = right()
    }

    var body: some View {
        if let onPress {
            Button(action: onPress) { content }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(accessibilityLabelOverride ?? spoken([label, value].compactMap { $0 }.joined(separator: ", ")))
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            content
        }
    }

    private var color: Color {
        switch tone { case .normal: p.text; case .accent: p.accent; case .late: p.late; case .dim: p.dim }
    }

    private var content: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(TypeStyle.body).foregroundStyle(color).lineLimit(2)
                if let detail { Text(detail).font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value).font(TypeStyle.body).foregroundStyle(p.dim).lineLimit(1).multilineTextAlignment(.trailing)
            }
            right
            if chevron { Text(open == true ? "⌄" : "›").font(TypeStyle.body).foregroundStyle(p.faint) }
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

extension ListRow where Right == EmptyView {
    init(_ label: String, value: String? = nil, detail: String? = nil, onPress: (() -> Void)? = nil,
         chevron: Bool? = nil, open: Bool? = nil, tone: Tone = .normal, selected: Bool = false,
         accessibilityLabel: String? = nil) {
        self.init(label, value: value, detail: detail, onPress: onPress, chevron: chevron, open: open, tone: tone,
                  selected: selected, accessibilityLabel: accessibilityLabel) { EmptyView() }
    }
}
