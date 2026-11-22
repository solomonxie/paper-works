import SwiftUI
import PaperWorksCore

/// Chooses which board event a baby-names plan belongs to.
struct EventPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    var current: String?
    var marksCurrent = true
    var onPick: (String?) -> Void
    var onNew: () -> Void

    private var events: [PaperWorksCore.Anchor] {
        let baby = Set(toolPlanKind(.babyNames)?.suggestedBy ?? [])
        return model.mine.anchors.sorted {
            let a = baby.contains($0.kind), b = baby.contains($1.kind)
            return a != b ? a : $0.date < $1.date
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Event") {
                    ForEach(events) { e in row(eventLabel(e), picked: current == e.id) { onPick(e.id) } }
                    row("No event", picked: current == nil) { onPick(nil) }
                }
                Section {
                    Button { dismiss(); onNew() } label: { Label("Add a new event…", systemImage: "plus") }
                }
            }
            .navigationTitle("Baby names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ title: String, picked: Bool, _ action: @escaping () -> Void) -> some View {
        Button { dismiss(); action() } label: {
            HStack {
                Text(title).foregroundStyle(p.text)
                Spacer()
                if picked && marksCurrent { Image(systemName: "checkmark").foregroundStyle(p.accent) }
            }
        }
    }
}
