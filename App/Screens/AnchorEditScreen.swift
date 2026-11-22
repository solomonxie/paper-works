import SwiftUI
import PaperWorksCore

private typealias Anchor = PaperWorksCore.Anchor

private enum Row { case what, place, when, end, precision, purpose }
private enum Confirm: Identifiable {
    case move, discard, delete
    var id: Self { self }
}

private let precisions = [
    PickerOption(value: "year", label: "just the year"),
    PickerOption(value: "month", label: "month and year"),
    PickerOption(value: "day", label: "to the day"),
]

private struct Draft: Equatable {
    var kind: String, label: String, place: String, note: String, location: String?
    var date: CivilDate, precision: DatePrecision, end: CivilDate?, purpose: String?
}

struct AnchorEditScreen: View {
    let anchorId: String?
    let kind: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p

    @State private var draft: Draft?
    @State private var start: Draft?
    @State private var open: Row?
    @State private var attach: [String] = []
    @State private var attachTools: [PlanKind] = []
    @State private var confirm: Confirm?

    private var existing: Anchor? { model.mine.anchors.first { $0.id == anchorId } }

    var body: some View {
        NavigationStack {
            Group {
                if let draft { form(Binding(get: { self.draft ?? draft }, set: { self.draft = $0 })) }
            }
            .background(p.bg)
            .navigationTitle(existing == nil ? "Add an event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!dirty)
                }
            }
        }
        .interactiveDismissDisabled(changed)
        .onAppear(perform: load)
        .alert(alertTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            alertButtons
        } message: {
            if let m = alertMessage { Text(m) }
        }
    }

    private func load() {
        guard draft == nil else { return }
        let startKind = existing?.kind ?? kind ?? "migrated"
        let d = Draft(
            kind: startKind, label: existing?.label ?? kindById(startKind)?.label ?? "",
            place: existing?.place ?? "", note: existing?.note ?? "", location: existing?.location,
            date: existing?.date ?? (startKind == "born" ? "1990-01-01" : model.now),
            precision: existing?.precision ?? .day, end: existing?.end, purpose: existing?.purpose)
        draft = d; start = d
        open = existing == nil ? .what : nil
    }

    private var changed: Bool { draft != start || !attach.isEmpty || !attachTools.isEmpty }
    private var kindDef: AnchorKind? { draft.flatMap { kindById($0.kind) } }
    private var endsBeforeStart: Bool {
        guard let d = draft, let end = d.end, kindDef?.ends != nil else { return false }
        return resolve(end, d.precision) < resolve(d.date, d.precision)
    }
    private var dirty: Bool { (existing == nil || changed) && !endsBeforeStart }

    // MARK: form

    private func form(_ d: Binding<Draft>) -> some View {
        let linked = isLinkedKind(d.wrappedValue.kind)
        let others = model.plan.people.filter { $0.id != model.mine.person.id }
        let years = 1900...(Int(model.now.prefix(4)) ?? 2026) + 40
        return ScrollView {
            VStack(spacing: 0) {
                Card {
                    ListRow("What", value: d.wrappedValue.label, onPress: { toggle(.what) }, open: open == .what)
                    if open == .what {
                        KindPicker(value: d.wrappedValue.kind, label: d.wrappedValue.label) { k, l in
                            d.wrappedValue.kind = k; d.wrappedValue.label = l
                            attach = []
                            attachTools = []
                            open = existing == nil ? .when : nil
                            Haptics.play(.selection)
                        }
                    }
                    PWDivider()
                    ListRow("Place", value: d.wrappedValue.location ?? "optional", onPress: { toggle(.place) }, open: open == .place)
                    if open == .place {
                        PlacePicker(value: d.wrappedValue.location) { v in
                            d.wrappedValue.location = v; open = nil; Haptics.play(.selection)
                        }
                    }
                    PWDivider()
                    ListRow("When", value: formatPrecise(d.wrappedValue.date, d.wrappedValue.precision),
                            onPress: { toggle(.when) }, open: open == .when)
                    if open == .when {
                        DateWheel(date: d.date, precision: d.wrappedValue.precision, years: years)
                    }
                    if let ends = kindDef?.ends {
                        PWDivider()
                        ListRow(ends, value: d.wrappedValue.end.map { formatPrecise($0, d.wrappedValue.precision) } ?? "optional",
                                onPress: {
                                    if d.wrappedValue.end == nil { d.wrappedValue.end = d.wrappedValue.date }
                                    toggle(.end)
                                }, open: open == .end)
                        if open == .end {
                            DateWheel(date: Binding(get: { d.wrappedValue.end ?? d.wrappedValue.date }, set: { d.wrappedValue.end = $0 }),
                                      precision: d.wrappedValue.precision, years: years)
                            PWButton(title: "No end date", kind: .plain) { d.wrappedValue.end = nil; open = nil }
                                .padding(.bottom, Space.md)
                        }
                    }
                    PWDivider()
                    UnfoldingPicker(label: "Precision", value: d.wrappedValue.precision.rawValue, options: precisions,
                                    open: open == .precision, onToggle: { toggle(.precision) }) { v in
                        d.wrappedValue.precision = DatePrecision(rawValue: v) ?? .day; open = nil
                    }
                    if let purposes = kindDef?.purposes {
                        PWDivider()
                        UnfoldingPicker(label: "Purpose", value: d.wrappedValue.purpose ?? "",
                                        options: purposes.map { PickerOption(value: $0.id, label: $0.label) } + [PickerOption(value: "", label: "Not set")],
                                        open: open == .purpose, onToggle: { toggle(.purpose) }) { v in
                            d.wrappedValue.purpose = v.isEmpty ? nil : v; open = nil
                        }
                    }
                    PWDivider()
                    HStack(spacing: Space.md) {
                        Text(linked ? "Who" : "Event name").font(TypeStyle.body).foregroundStyle(p.text)
                        TextField("", text: d.place, prompt: Text(placeholder(d.wrappedValue.kind)).foregroundStyle(p.faint))
                            .font(TypeStyle.body).foregroundStyle(p.dim).multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onTapGesture { open = nil }
                            .accessibilityLabel(linked ? "Who" : "Event name")
                    }
                    .padding(.horizontal, Space.lg).frame(minHeight: 48)
                    if linked, !others.isEmpty {
                        FlowChips(names: others.map(\.name), picked: d.wrappedValue.place) { d.wrappedValue.place = $0 }
                    }
                }

                SectionHeader("Notes")
                Card {
                    TextField("", text: d.note, prompt: Text("Case numbers, who to call, what was sent").foregroundStyle(p.faint), axis: .vertical)
                        .font(TypeStyle.body).foregroundStyle(p.text)
                        .padding(Space.lg).padding(.top, -Space.xs)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .accessibilityLabel("Notes")
                }

                if endsBeforeStart, let ends = kindDef?.ends { note("\(ends) is before it starts.", p.late) }
                if resolve(d.wrappedValue.date, d.wrappedValue.precision) > model.now {
                    note("That's ahead — it'll show as a plan, not a fact.", p.dim)
                }

                let unlocks = unlocking(d.wrappedValue)
                let tools = toolPlanKinds(suggestedBy: d.wrappedValue.kind)
                if !unlocks.isEmpty || !tools.isEmpty {
                    SectionHeader("Plans this unlocks")
                    Card {
                        Rows {
                            ForEach(tools, id: \.kind) { t in
                                if model.toolPlan(t.kind, anchorId: anchorId) != nil {
                                    ListRow(t.title, value: "✓ added", chevron: false)
                                } else {
                                    CheckRow(label: t.title, checked: attachTools.contains(t.kind),
                                             onToggle: { toggleTool(t.kind) },
                                             detail: "\(t.summary) · adds on Save")
                                }
                            }
                            ForEach(unlocks, id: \.pb.id) { u in
                                if u.attached {
                                    ListRow(u.pb.title, value: "✓ attached", chevron: false)
                                } else {
                                    CheckRow(label: u.pb.title, checked: attach.contains(u.pb.id),
                                             onToggle: { toggleAttach(u.pb.id) },
                                             detail: "\(u.pb.steps.count) steps\(u.detail) · attaches on Save")
                                }
                            }
                        }
                    }
                }

                if existing != nil {
                    PWButton(title: "Delete this event", kind: .secondary, destructive: true) { confirm = .delete }
                        .padding(Space.lg).padding(.top, Space.xl)
                }
            }
            .padding(.top, Space.lg).padding(.bottom, 80)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).font(TypeStyle.caption).foregroundStyle(color)
            .padding(.horizontal, Space.xl).padding(.top, Space.sm).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ row: Row) { open = open == row ? nil : row }
    private func toggleAttach(_ id: String) {
        if let i = attach.firstIndex(of: id) { attach.remove(at: i) } else { attach.append(id) }
    }

    private func toggleTool(_ k: PlanKind) {
        if let i = attachTools.firstIndex(of: k) { attachTools.remove(at: i) } else { attachTools.append(k) }
    }

    private struct Unlock { var pb: Playbook; var attached: Bool; var detail: String }

    private func unlocking(_ d: Draft) -> [Unlock] {
        let me = model.mine.person.id
        let draftAnchor = Anchor(id: anchorId ?? "", kind: d.kind, label: d.label, location: d.location, date: d.date,
                                 personId: existing?.personId ?? me, linkId: existing?.linkId)
        let who = d.place.trimmingCharacters(in: .whitespaces)
        return plansFor(draftAnchor, model.mine.where, model.playbooks, model.mine.anchors).compactMap { pb in
            let from = opens(d.kind, pb)
            let on = countsFrom(pb, draftAnchor, model.plan.anchors)
            if from == .born, on == nil { return nil }
            if from == .child, on == nil, who.isEmpty { return nil }
            let attached = on.map { o in model.plan.tracks.contains { $0.playbookId == pb.id && $0.anchorId == o.id } } ?? false
            let detail = from == .born ? " · counts from Born" : from == .child ? " · on \(who)'s board" : ""
            return Unlock(pb: pb, attached: attached, detail: detail)
        }
    }

    // MARK: actions

    private func cancel() { changed ? (confirm = .discard) : dismiss() }

    private func save() {
        guard let d = draft else { return }
        if let e = existing,
           resolve(e.date, e.precision) != resolve(d.date, d.precision) || e.end != d.end || e.purpose != d.purpose,
           !stepsOnAnchor.isEmpty {
            confirm = .move
        } else {
            commit()
        }
    }

    private var stepsOnAnchor: [PlannedStep] {
        let ids = Set(model.mine.tracks.filter { $0.anchorId == anchorId }.map(\.id))
        return model.mine.view.steps.filter { ids.contains($0.trackId) }
    }

    private func commit() {
        guard let d = draft else { return }
        let linked = isLinkedKind(d.kind)
        let def = kindById(d.kind)
        let trimmed = d.place.trimmingCharacters(in: .whitespacesAndNewlines)
        var a = existing ?? Anchor(id: "", kind: d.kind, label: d.label, date: d.date)
        a.kind = d.kind
        a.label = d.label.trimmingCharacters(in: .whitespaces).isEmpty ? "An event" : d.label.trimmingCharacters(in: .whitespaces)
        a.place = trimmed.isEmpty ? nil : trimmed
        let note = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
        a.note = note.isEmpty ? nil : note
        a.location = d.location
        a.date = d.date
        a.precision = d.precision
        a.end = def?.ends != nil ? d.end : nil
        a.purpose = def?.purposes != nil ? d.purpose : nil
        let id = model.saveAnchor(a, attach: attach, withName: linked ? d.place : nil)
        for k in attachTools { model.addToolPlan(k, anchorId: id) }
        Haptics.play(.success)
        dismiss()
    }

    // MARK: alerts

    private var alertTitle: String {
        guard let e = existing, let d = draft else { return existing == nil ? "Discard this event?" : "" }
        switch confirm {
        case .move: return e.date == d.date ? "Update “\(e.label)”?" : "Move “\(e.label)” to \(formatPrecise(d.date, d.precision))?"
        case .delete: return "Delete “\(e.label)”?"
        default: return "Discard your changes?"
        }
    }

    private var alertMessage: String? {
        switch confirm {
        case .move:
            let steps = stepsOnAnchor
            let done = steps.filter { $0.scheduled.status == .done }.count
            return "\(steps.count - done) steps get rescheduled.\(done > 0 ? " \(done) already done keep their real dates." : "")"
        case .delete:
            guard let e = existing else { return nil }
            let n = model.plan.tracks.filter { $0.anchorId == e.id }.count
            let also = model.plan.anchors
                .filter { e.linkId != nil && $0.linkId == e.linkId && $0.id != e.id }
                .compactMap { a in model.plan.people.first { $0.id == (a.personId ?? ME) }?.name }
            let parts = [
                n > 0 ? "\(n) plan\(n == 1 ? "" : "s") lose\(n == 1 ? "s" : "") their event and detach." : "",
                also.isEmpty ? "" : "Also removed from \(also.joined(separator: " and "))’s timeline.",
            ].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        default: return nil
        }
    }

    @ViewBuilder private var alertButtons: some View {
        switch confirm {
        case .move:
            Button("Cancel", role: .cancel) {}
            Button(existing?.date == draft?.date ? "Update" : "Move it") { commit() }
        case .delete:
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let e = existing { model.deleteAnchor(e.id) }
                dismiss()
            }
        default:
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        }
    }

    private func placeholder(_ kind: String) -> String {
        [
            "born": "optional", "graduated": "a degree", "migrated": "a country", "moved-city": "a city",
            "school-start": "the child's name", "child-born": "the child's name", "visa-lodge": "the program",
            "visa-granted": "the permit", "visit": "who: Mom and Dad…", "trip": "a country",
        ][kind] ?? "optional"
    }
}

private struct FlowChips: View {
    let names: [String]
    let picked: String
    let pick: (String) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(names, id: \.self) { n in
                    Button { pick(n) } label: {
                        Text(n).font(TypeStyle.caption).foregroundStyle(p.accent)
                            .padding(.horizontal, Space.md).padding(.vertical, Space.xs + 2)
                            .background(Capsule().fill(picked == n ? p.accentSoft : p.bg))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked == n ? .isSelected : [])
                }
            }
            .padding(.horizontal, Space.lg).padding(.bottom, Space.md)
        }
    }
}
