import SwiftUI

struct SwipeAction: Identifiable {
    let label: String
    let color: Color
    let perform: () -> Void
    var id: String { label }
}

extension View {
    /// Swipe ← for trailing actions, → for leading ones; VoiceOver gets them as custom actions.
    /// Effective inside a List row; elsewhere use the VoiceOver actions only.
    func pwSwipe(leading: [SwipeAction] = [], trailing: [SwipeAction] = []) -> some View {
        self
            .swipeActions(edge: .leading, allowsFullSwipe: false) { swipeButtons(leading) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeButtons(trailing) }
    }

    @ViewBuilder private func swipeButtons(_ actions: [SwipeAction]) -> some View {
        ForEach(actions) { a in Button(a.label, action: a.perform).tint(a.color) }
    }
}
