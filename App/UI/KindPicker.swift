import SwiftUI
import PaperWorksCore

/// The `What` list, unfolded in place with a filter field on top. Typing an unlisted kind keeps it as free text.
struct KindPicker: View {
    let value: String
    let label: String
    let onPick: (_ kind: String, _ label: String) -> Void
    @State private var q = ""
    @FocusState private var focused: Bool
    @Environment(\.palette) private var p

    private var needle: String { q.trimmingCharacters(in: .whitespaces).lowercased() }
    private var matches: [AnchorKind] {
        ANCHOR_KINDS.filter { needle.isEmpty || $0.label.lowercased().contains(needle) || $0.group.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search or type your own", text: $q)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(submit)
                .font(TypeStyle.body).foregroundStyle(p.text)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .background(RoundedRectangle(cornerRadius: 8).fill(p.bg))
                .padding(.horizontal, Space.lg).padding(.top, Space.sm)
                .accessibilityLabel("Search kinds of event")
            ForEach(Array(matches.enumerated()), id: \.element.id) { i, k in
                if k.group != matches[safe: i - 1]?.group {
                    Text(k.group.uppercased()).font(TypeStyle.heading).tracking(TypeStyle.headingTracking)
                        .foregroundStyle(p.dim).padding(.top, Space.md).padding(.horizontal, Space.lg)
                }
                option(mark: k.id == value ? "✓" : "", text: k.label, color: p.text, selected: k.id == value) {
                    onPick(k.id, k.label)
                }
            }
            if !needle.isEmpty, !matches.contains(where: { $0.label.lowercased() == needle }) {
                option(mark: "+", text: "Use “\(q.trimmingCharacters(in: .whitespaces))”", color: p.accent, selected: false) {
                    onPick("custom", q.trimmingCharacters(in: .whitespaces))
                }
            }
            if value == "custom", needle.isEmpty {
                option(mark: "✓", text: label, color: p.text, selected: true) {}
            }
        }
        .padding(.bottom, Space.sm)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !needle.isEmpty else { return }
        if let exact = matches.first, exact.label.lowercased() == needle { onPick(exact.id, exact.label) }
        else { onPick("custom", q.trimmingCharacters(in: .whitespaces)) }
    }

    private func option(mark: String, text: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Text(mark).foregroundStyle(p.accent).frame(width: 18)
                Text(text).font(TypeStyle.body).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Space.sm + 2).padding(.horizontal, Space.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
