import SwiftUI
import PaperWorksCore

/// The `Place` row unfolded: search the bundled city list, or keep whatever was typed.
/// `near` is a country name that ranks first (e.g. the user's own country).
struct PlacePicker: View {
    var value: String?
    var near: String? = "Canada"
    let onPick: (String?) -> Void
    @State private var q = ""
    @FocusState private var focused: Bool
    @Environment(\.palette) private var p

    private var typed: String { q.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let matches = searchPlaces(typed, limit: 8, near: near)
        let labels = matches.map { placeLabel($0) }
        let exact = labels.contains { $0.lowercased() == typed.lowercased() }
        VStack(alignment: .leading, spacing: 0) {
            TextField("City, town, or type your own", text: $q)
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { if !typed.isEmpty { onPick(labels.first ?? typed) } }
                .font(TypeStyle.body).foregroundStyle(p.text)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .background(RoundedRectangle(cornerRadius: 8).fill(p.bg))
                .padding(.horizontal, Space.lg).padding(.top, Space.sm)
                .accessibilityLabel("Search places")
            ForEach(Array(matches.enumerated()), id: \.offset) { i, m in
                row(labels[i]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(m.name).font(TypeStyle.body).foregroundStyle(p.text).lineLimit(1)
                        Text([m.admin != m.name ? m.admin : "", m.country].filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(1)
                    }
                } action: { onPick(labels[i]) }
            }
            if !typed.isEmpty, !exact {
                row("Use \(typed)") { Text("Use “\(typed)”").font(TypeStyle.body).foregroundStyle(p.accent) } action: { onPick(typed) }
            }
            if typed.isEmpty, value != nil {
                row("Remove the place") { Text("Remove the place").font(TypeStyle.body).foregroundStyle(p.late) } action: { onPick(nil) }
            }
        }
        .padding(.bottom, Space.sm)
        .onAppear { focused = true }
    }

    private func row<C: View>(_ label: String, @ViewBuilder content: () -> C, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, Space.lg).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
