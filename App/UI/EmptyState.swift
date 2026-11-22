import SwiftUI

struct EmptyState: View {
    let title: String
    var message: String?
    var action: String?
    var onAction: (() -> Void)?
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: Space.sm) {
            Text(title).font(TypeStyle.headline).foregroundStyle(p.text).multilineTextAlignment(.center)
            if let message { Text(message).font(TypeStyle.body).foregroundStyle(p.dim).multilineTextAlignment(.center) }
            if let action, let onAction {
                PWButton(title: action, kind: .primary, action: onAction)
                    .padding(.top, Space.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xxl)
    }
}
