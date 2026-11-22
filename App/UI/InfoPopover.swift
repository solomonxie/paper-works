import SwiftUI

/// The ⓘ beside a heading. Pass `trigger` to use something other than ⓘ (e.g. ▲▼).
struct InfoPopover<Trigger: View>: View {
    let text: String
    var title: String?
    var label = "More about this"
    @ViewBuilder var trigger: Trigger
    @State private var open = false
    @Environment(\.palette) private var p

    var body: some View {
        Button { open = true } label: { trigger.padding(Space.xs) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .popover(isPresented: $open, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    if let title { Text(title).font(TypeStyle.label.weight(.semibold)).foregroundStyle(p.text) }
                    Text(text).font(TypeStyle.body).foregroundStyle(p.text)
                }
                .padding(Space.lg)
                .frame(maxWidth: 300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
            }
    }
}

extension InfoPopover where Trigger == InfoGlyph {
    init(text: String, title: String? = nil, label: String = "More about this") {
        self.init(text: text, title: title, label: label) { InfoGlyph() }
    }
}

struct InfoGlyph: View {
    @Environment(\.palette) private var p
    var body: some View { Text("ⓘ").font(TypeStyle.body).foregroundStyle(p.accent) }
}
