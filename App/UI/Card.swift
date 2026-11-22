import SwiftUI

struct Card<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .padding(.horizontal, Space.lg)
    }
}

/// Hairline between rows inside a card, inset to the text.
struct PWDivider: View {
    var inset: CGFloat = Space.lg
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle().fill(p.hairline).frame(height: 1 / UIScreen.main.scale).padding(.leading, inset)
    }
}

/// Interleaves dividers between children.
struct Rows<Content: View>: View {
    var inset: CGFloat = Space.lg
    @ViewBuilder var content: Content

    var body: some View {
        _VariadicView.Tree(Interleave(inset: inset)) { content }
    }

    private struct Interleave: _VariadicView_UnaryViewRoot {
        let inset: CGFloat
        func body(children: _VariadicView.Children) -> some View {
            ForEach(Array(children.enumerated()), id: \.offset) { i, child in
                if i > 0 { PWDivider(inset: inset) }
                child
            }
        }
    }
}
