import SwiftUI

struct PickerOption: Identifiable, Equatable {
    let value: String
    let label: String
    /// Shown in the closed row when the full label is too long.
    var short: String?
    var group: String?
    var id: String { value }
}

/// A form row whose options unfold in place and push the rest down. No Cancel/Done.
struct UnfoldingPicker: View {
    let label: String
    let value: String
    let options: [PickerOption]
    let open: Bool
    let onToggle: () -> Void
    let onSelect: (String) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        let selected = options.first { $0.value == value }
        VStack(spacing: 0) {
            ListRow(label, value: selected?.short ?? selected?.label ?? value, onPress: onToggle, open: open)
            if open {
                Rectangle().fill(p.hairline).frame(height: 1 / UIScreen.main.scale)
                ForEach(Array(options.enumerated()), id: \.element.id) { i, option in
                    if let g = option.group, g != options[safe: i - 1]?.group {
                        Text(g.uppercased()).font(TypeStyle.heading).tracking(TypeStyle.headingTracking)
                            .foregroundStyle(p.dim)
                            .padding(.top, Space.md).padding(.horizontal, Space.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { onSelect(option.value) } label: {
                        HStack(spacing: Space.sm) {
                            Text(option.value == value ? "✓" : "").foregroundStyle(p.accent).frame(width: 18)
                            Text(option.label).font(TypeStyle.body).foregroundStyle(p.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, Space.md).padding(.horizontal, Space.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(option.value == value ? .isSelected : [])
                }
            }
        }
        .animation(.default, value: open)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
