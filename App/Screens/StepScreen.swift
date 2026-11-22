import SwiftUI
import PaperWorksCore

private let SNOOZE_OPTIONS: [(label: String, days: Int)] = [("1 week", 7), ("2 weeks", 14), ("1 month", 30), ("3 months", 91)]

/// Snooze from today. The step comes back to ACT NOW when it ends.
struct SnoozeDialog: ViewModifier {
    @Binding var instanceId: String?
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Snooze until…",
            isPresented: Binding(get: { instanceId != nil }, set: { if !$0 { instanceId = nil } }),
            titleVisibility: .visible,
            presenting: instanceId
        ) { id in
            ForEach(SNOOZE_OPTIONS, id: \.label) { option in
                Button(option.label) { model.snooze(id, until: addDays(model.now, option.days)) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension View {
    func snoozeDialog(_ instanceId: Binding<String?>) -> some View { modifier(SnoozeDialog(instanceId: instanceId)) }
}

private enum Panel { case doneOn, due }

struct StepScreen: View {
    let instanceId: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var panel: Panel?
    @State private var pickDate: CivilDate = today()
    @State private var snoozing: String?
    @State private var editingNote = false
    @State private var noteText = ""
    @State private var confirmDone = false

    private var step: PlannedStep? { model.view.steps.first { $0.instanceId == instanceId } }
    private var instance: StepInstance? { model.plan.instances.first { $0.id == instanceId } }

    var body: some View {
        Group {
            if let step, let instance {
                content(step, instance)
            } else {
                Text("This step is no longer in your plan.")
                    .font(TypeStyle.body).foregroundStyle(p.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
            }
        }
        .background(p.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let step, let instance {
                ToolbarItem(placement: .topBarTrailing) { menu(step, instance) }
            }
        }
        .snoozeDialog($snoozing)
        .alert("Note", isPresented: $editingNote) {
            TextField("Note", text: $noteText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.setNote(instanceId, noteText) }
        }
        .alert("Every document is in.", isPresented: $confirmDone) {
            Button("Not yet", role: .cancel) {}
            Button("Mark done") { markDone() }
        } message: {
            Text("Mark \"\(step?.title ?? "this step")\" done?")
        }
    }

    // MARK: actions

    private func haptic(_ kind: HapticKind) { if model.settings.haptics { Haptics.play(kind) } }

    private func markDone() {
        haptic(.success)
        model.markDone(instanceId)
    }

    private func editNote(_ instance: StepInstance) {
        noteText = instance.note ?? ""
        editingNote = true
    }

    private func redo(_ step: PlannedStep, firstOpenConsumer: PlannedStep?) {
        guard let consumer = firstOpenConsumer else {
            model.reopen(instanceId)
            return
        }
        if let id = model.planRedo(step.trackId, step.stepId, consumer.stepId) { model.push(.step(instanceId: id)) }
    }

    private func toggleDocument(_ name: String, step: PlannedStep, instance: StepInstance, open: Bool, docsDone: Int) {
        let checking = !instance.checkedDocuments.contains(name)
        model.toggleDocument(instanceId, name)
        haptic(.selection)
        if checking && open && docsDone + 1 == step.template.documents.count { confirmDone = true }
    }

    private func menu(_ step: PlannedStep, _ instance: StepInstance) -> some View {
        Menu {
            if step.status == .skipped {
                Button("Restore") { model.restore(instanceId) }
            } else {
                Button("Not for me", role: .destructive) { model.skip(instanceId) }
            }
            Button(instance.note == nil ? "Add a note" : "Edit note") { editNote(instance) }
            Button("Move due date…") {
                pickDate = step.dueBy
                panel = .due
            }
            Button("View in playbook") { model.push(.playbook(playbookId: step.playbook.id, trackId: step.trackId)) }
        } label: {
            Text("⋯").font(TypeStyle.headline).foregroundStyle(p.accent)
        }
        .accessibilityLabel("More")
    }

    // MARK: body

    @ViewBuilder private func content(_ step: PlannedStep, _ instance: StepInstance) -> some View {
        let now = model.now
        let trackSteps = model.view.steps.filter { $0.trackId == step.trackId }
        let blocks = trackSteps.filter { $0.template.dependsOn.contains(step.stepId) }
        let waitsFor = trackSteps.filter { step.template.dependsOn.contains($0.stepId) }
        let clash = model.view.clashes.first { $0.trackId == step.trackId && $0.source.stepId == step.stepId }
        let open = step.status == .pending || step.status == .snoozed
        let blocked = open && !step.blockedByLate.isEmpty
        let blocker = trackSteps.first { $0.stepId == step.blockedByLate.first }
        let expired = step.status == .done && (step.expiresOn.map { $0 < now } ?? false)
        let firstOpenConsumer = blocks.first { $0.status == .pending || $0.status == .snoozed }
        let docsDone = step.template.documents.filter { instance.checkedDocuments.contains($0) }.count
        let prepDone = step.template.prepare.filter { instance.checkedPrepare.contains($0) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head(step, now)
                datesCard(step, instance, now: now, blocks: blocks, open: open, blocked: blocked, expired: expired)
                if let panel { panelCard(panel, step, instance, now: now) }

                if let clash, !expired {
                    alertCard {
                        Button {
                            model.push(.step(instanceId: clash.consumer.instanceId))
                        } label: {
                            Text("⚠ Expires \(formatDate(step.expiresOn ?? clash.source.dueBy)) — \(clash.gapDays) days before \(clash.consumer.title) needs it. ›")
                                .font(TypeStyle.body).foregroundStyle(p.text).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        PWButton(title: "Plan a redo") { redo(step, firstOpenConsumer: firstOpenConsumer) }
                    }
                }
                if expired {
                    alertCard {
                        Text(firstOpenConsumer.map { "\($0.title) still needs it." } ?? "Redo this step if it is needed again.")
                            .font(TypeStyle.body).foregroundStyle(p.text)
                        PWButton(title: "Redo", kind: .primary) { redo(step, firstOpenConsumer: firstOpenConsumer) }
                    }
                }

                if open {
                    HStack(spacing: Space.md) {
                        markDoneButton(now: now)
                        PWButton(title: "Snooze…") { snoozing = instanceId }
                    }
                    .padding(.horizontal, Space.lg).padding(.top, Space.lg)
                }
                if blocked, let blocker {
                    note("← waiting on \"\(blocker.title)\"", color: p.dim)
                }
                if open && panel == nil {
                    note("Long-press Mark done if it happened on an earlier day.", color: p.faint)
                }

                if !step.template.documents.isEmpty {
                    SectionHeader("Documents to obtain") { Count(n: docsDone, of: step.template.documents.count) }
                    Card {
                        Rows(inset: Space.lg + 22 + Space.md) {
                            ForEach(step.template.documents, id: \.self) { d in
                                CheckRow(
                                    label: d,
                                    checked: instance.checkedDocuments.contains(d),
                                    onToggle: { toggleDocument(d, step: step, instance: instance, open: open, docsDone: docsDone) },
                                    onOpen: { model.push(.document(documentId: docId(d))) })
                            }
                        }
                    }
                }

                if !step.template.prepare.isEmpty {
                    SectionHeader(
                        "Prepare",
                        info: "Prep never holds up a later step — it's here so nothing is forgotten, not to gate anything."
                    ) { Count(n: prepDone, of: step.template.prepare.count) }
                    Card {
                        Rows(inset: Space.lg + 22 + Space.md) {
                            ForEach(step.template.prepare, id: \.self) { x in
                                CheckRow(label: x, checked: instance.checkedPrepare.contains(x)) {
                                    haptic(.selection)
                                    model.togglePrepare(instanceId, x)
                                }
                            }
                        }
                    }
                }

                SectionHeader(
                    "How to",
                    info: "How this paperwork usually goes, written by the playbook's author. Rules change — check the official source before relying on it.")
                howTo(step, instance)

                if !blocks.isEmpty { stepList("Blocks", blocks) }
                if !waitsFor.isEmpty { stepList("Waits for", waitsFor) }
            }
            .padding(.bottom, 120)
        }
    }

    private func head(_ step: PlannedStep, _ now: CivilDate) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(step.title).font(TypeStyle.title).foregroundStyle(p.text).accessibilityAddTraits(.isHeader)
            Text("\(step.playbook.title) · step \(step.index) of \(step.total)")
                .font(TypeStyle.caption).foregroundStyle(p.dim)
            AppliesIf(ages: step.template.ages, conditions: step.template.conditions)
            Disclaimer(playbook: step.playbook, now: now)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.lg).padding(.top, Space.sm).padding(.bottom, Space.md)
    }

    private func datesCard(_ step: PlannedStep, _ instance: StepInstance, now: CivilDate, blocks: [PlannedStep],
                           open: Bool, blocked: Bool, expired: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                if step.status == .done {
                    HStack(spacing: Space.sm) {
                        Button {
                            pickDate = step.startBy
                            panel = panel == .doneOn ? nil : .doneOn
                        } label: {
                            (Text("✓ Done · \(formatDate(step.startBy)) ").font(TypeStyle.label).foregroundStyle(p.done)
                                + Text("Change ›").font(TypeStyle.caption).foregroundStyle(p.accent))
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Done on \(formatDate(step.startBy)). Change the date")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Undo") { model.reopen(instanceId) }.buttonStyle(.pwPlain)
                    }
                    if let expires = step.expiresOn {
                        Text(expired ? "⚠ Expired \(formatDate(expires))." : "valid until \(formatDate(expires))")
                            .font(TypeStyle.caption).foregroundStyle(expired ? p.late : p.dim)
                    }
                } else if step.status == .skipped {
                    HStack(spacing: Space.sm) {
                        Text("Not for me").font(TypeStyle.label).foregroundStyle(p.dim).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Restore") { model.restore(instanceId) }.buttonStyle(.pwPlain)
                    }
                    if !blocks.isEmpty {
                        Text("\(blocks.count) later step\(blocks.count == 1 ? " no longer waits" : "s no longer wait") for it.")
                            .font(TypeStyle.caption).foregroundStyle(p.dim)
                    }
                } else {
                    dateLine("start by") {
                        if blocked {
                            Text("— blocked").font(TypeStyle.caption).foregroundStyle(p.dim)
                        } else {
                            DatePair(date: step.startBy, now: now, lateRed: false)
                        }
                    }
                    Button {
                        pickDate = step.dueBy
                        panel = panel == .due ? nil : .due
                    } label: {
                        dateLine("due by") {
                            HStack {
                                (Text(formatDate(step.dueBy)).foregroundStyle(p.text)
                                    + Text(instance.dueOverride != nil ? "  · moved by you" : "  · suggested").foregroundStyle(p.dim))
                                    .font(TypeStyle.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Change ›").font(TypeStyle.caption).foregroundStyle(p.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Due by \(formatDate(step.dueBy)), \(instance.dueOverride != nil ? "moved by you" : "suggested"). Change")
                    if let until = step.snoozedUntil, until > now {
                        HStack(spacing: Space.sm) {
                            Text("snoozed \(formatSpan(diffDays(now, until))) · until \(formatShort(until))")
                                .font(TypeStyle.caption).foregroundStyle(p.dim).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Clear") { model.clearSnooze(instanceId) }.buttonStyle(.pwPlain)
                        }
                    }
                }
                if let valid = step.template.validForDays {
                    dateLine("valid") {
                        HStack {
                            Text("\(formatDuration(valid)) from issue").font(TypeStyle.caption).foregroundStyle(p.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            InfoPopover(text: validInfo(step, valid), title: "Why not earlier")
                        }
                    }
                }
                if step.atRisk && open {
                    Text("⚠ A step before it runs late, so this starts after it ideally should.")
                        .font(TypeStyle.caption).foregroundStyle(p.warn)
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func validInfo(_ step: PlannedStep, _ valid: Int) -> String {
        var s = "\(step.title) is usually accepted for \(formatDuration(valid)) from issue."
        if let earliest = step.earliestStart {
            s += " Starting before \(formatDate(earliest)) risks it expiring before \(formatShort(step.dueBy)) — paying for it twice."
        }
        return s
    }

    private func dateLine<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: Space.md) {
            Text(label).font(TypeStyle.caption).foregroundStyle(p.dim).frame(width: 64, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 24)
    }

    private func panelCard(_ panel: Panel, _ step: PlannedStep, _ instance: StepInstance, now: CivilDate) -> some View {
        let year = Int(now.prefix(4)) ?? 2026
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                Text(panel == .doneOn ? "Done on" : "Move the due date to")
                    .font(TypeStyle.label).foregroundStyle(p.text).padding(.horizontal, Space.lg)
                DateWheel(date: $pickDate, years: (year - 30)...(year + (panel == .doneOn ? 0 : 30)))
                    .frame(maxWidth: .infinity)
                HStack(spacing: Space.md) {
                    Spacer()
                    Button("Cancel") { self.panel = nil }.buttonStyle(.pwPlain)
                    if panel == .due && instance.dueOverride != nil {
                        Button("Reset") {
                            model.moveDue(instanceId, nil)
                            self.panel = nil
                        }.buttonStyle(.pwPlain)
                    }
                    Button(panel == .doneOn ? (step.status == .done ? "Save" : "Mark done") : "Move it") {
                        if panel == .doneOn {
                            haptic(.success)
                            model.markDone(instanceId, on: pickDate)
                        } else {
                            model.moveDue(instanceId, pickDate)
                        }
                        self.panel = nil
                    }
                    .buttonStyle(.pwPrimary)
                    .disabled(panel == .doneOn && pickDate > now)
                }
                .padding(Space.lg)
            }
            .padding(.top, Space.md)
        }
        .padding(.top, Space.md)
    }

    private func alertCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) { content() }
                .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                .background(p.lateSoft)
        }
        .padding(.top, Space.md)
    }

    private func markDoneButton(now: CivilDate) -> some View {
        Text("Mark done")
            .font(TypeStyle.label.weight(.semibold)).foregroundStyle(p.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(p.accent))
            .contentShape(Rectangle())
            .onTapGesture { markDone() }
            .onLongPressGesture {
                pickDate = now
                panel = panel == .doneOn ? nil : .doneOn
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mark done")
            .accessibilityHint("Long-press to pick the day it was done")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { markDone() }
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text).font(TypeStyle.caption).foregroundStyle(color)
            .padding(.horizontal, Space.lg).padding(.top, Space.sm)
    }

    private func howTo(_ step: PlannedStep, _ instance: StepInstance) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                if let howTo = step.template.howTo, !howTo.isEmpty {
                    ForEach(Array(howTo.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line)).font(TypeStyle.body).foregroundStyle(p.text)
                    }
                } else {
                    Text("Nothing written yet.").font(TypeStyle.body).foregroundStyle(p.dim)
                }
                if let n = instance.note, !n.isEmpty {
                    Button { editNote(instance) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Divider().overlay(p.hairline).padding(.bottom, Space.xs)
                            Text("YOUR NOTE").font(TypeStyle.caption).foregroundStyle(p.dim)
                            Text(n).font(TypeStyle.body).foregroundStyle(p.text).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Add a note") { editNote(instance) }.buttonStyle(.pwPlain).padding(.top, Space.xs)
                }
            }
            .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func stepList(_ title: String, _ steps: [PlannedStep]) -> some View {
        SectionHeader(title)
        Card {
            Rows(inset: Space.lg + 18 + Space.sm) {
                ForEach(steps, id: \.instanceId) { s in
                    StepRow(step: s.scheduled, now: model.now, move: model.moves[s.instanceId]) {
                        model.push(.step(instanceId: s.instanceId))
                    }
                }
            }
        }
    }
}

private struct Count: View {
    let n: Int
    let of: Int
    @Environment(\.palette) private var p
    var body: some View {
        Text("\(n)/\(of)\(n == of ? " ✓" : "")").font(TypeStyle.caption).foregroundStyle(n == of ? p.done : p.dim)
    }
}
