import SwiftUI
import PaperWorksCore

private typealias Anchor = PaperWorksCore.Anchor

private enum PersonRow { case relation, date }

private let relations = [
    PickerOption(value: "child", label: "Child"),
    PickerOption(value: "partner", label: "Partner"),
    PickerOption(value: "parent", label: "Parent"),
]

struct PersonScreen: View {
    let mode: PersonMode
    let personId: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    @State private var name = ""
    @State private var relation = "child"
    @State private var date = ""
    @State private var open: PersonRow?
    @FocusState private var focused: Bool

    private var current: Person { model.mine.person }
    private var ownBorn: Anchor? { model.mine.anchors.first { $0.kind == "born" } }
    private var ready: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var whose: String { current.id == ME ? "you" : current.name }
    private var possessive: String { whose == "you" ? "your" : "\(whose)’s" }
    private var fixedBorn: Anchor? { relation == "parent" ? ownBorn : nil }
    private var title: String {
        switch mode { case .rename: "Rename"; case .new: "New person"; case .link: "Link to \(whose)" }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Card {
                        HStack(spacing: Space.md) {
                            Text("Name").font(TypeStyle.body).foregroundStyle(p.text)
                            TextField("", text: $name, prompt: Text("Their name").foregroundStyle(p.faint))
                                .font(TypeStyle.body).foregroundStyle(p.dim).multilineTextAlignment(.trailing)
                                .focused($focused).submitLabel(.done).onSubmit(save)
                                .onTapGesture { open = nil }
                                .accessibilityLabel("Name")
                        }
                        .padding(.horizontal, Space.lg).frame(minHeight: 48)
                        if mode == .link { linkRows }
                    }
                    if mode == .link {
                        SectionHeader("What happens")
                        note(whatHappens)
                    } else if mode == .new {
                        note("A separate board with its own dates and plans, not tied to anyone.")
                    }
                }
                .padding(.top, Space.lg).padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(p.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .link ? "Link" : "Save", action: save).fontWeight(.semibold).disabled(!ready)
                }
            }
        }
        .onAppear {
            if date.isEmpty { date = model.now }
            if mode == .rename { name = model.plan.people.first { $0.id == personId }?.name ?? "" }
            if mode != .link { focused = true }
        }
    }

    @ViewBuilder private var linkRows: some View {
        PWDivider()
        UnfoldingPicker(label: "Is your", value: relation, options: relations, open: open == .relation,
                        onToggle: { open = open == .relation ? nil : .relation }) { v in
            relation = v; open = nil
        }
        PWDivider()
        let label = relation == "child" ? "Born" : relation == "parent" ? "\(current.name) born" : "Married"
        if let b = fixedBorn {
            ListRow(label, value: formatPrecise(b.date, b.precision))
        } else {
            ListRow(label, value: formatPrecise(date, .day), onPress: { open = open == .date ? nil : .date }, open: open == .date)
            if open == .date {
                DateWheel(date: $date, years: 1900...((Int(model.now.prefix(4)) ?? 2026) + 5))
            }
        }
    }

    private var whatHappens: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        switch relation {
        case "child": return "“\(n.isEmpty ? "Child" : n) born” goes on \(possessive) timeline, and \(n.isEmpty ? "they" : n) get a board of their own that starts on that date."
        case "parent": return "\(n.isEmpty ? "They" : n) get a board with “\(current.name) born” on it, tied to \(possessive) birth date."
        default: return "The wedding goes on both timelines. Moving the date on one moves it on the other."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(TypeStyle.caption).foregroundStyle(p.dim)
            .padding(.horizontal, Space.xl).padding(.top, Space.sm).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard ready else { return }
        switch mode {
        case .rename: if let personId { model.renamePerson(personId, name) }
        case .new: model.addPerson(name)
        case .link:
            if let id = model.linkPerson(name, RelatedPerson(rawValue: relation) ?? .child, date, .day) {
                model.switchPerson(id)
            }
        }
        Haptics.play(.success)
        dismiss()
    }
}
